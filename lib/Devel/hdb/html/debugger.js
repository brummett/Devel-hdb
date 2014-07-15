function Debugger(sel) {
    var dbg = this;
    var $elt = this.$elt = $(sel);

    this.filewindowDiv = $elt.find('div#filewindow');
    this.stackDiv = $elt.find('div#stack');
    this.watchDiv = $elt.find('div#watch-expressions');

    // templates
    Handlebars.registerHelper('ifDefined', function(val, options) {
        if ((val !== undefined) && (val !== null) && (val !== '')) {
            return options.fn(this)
        } else {
            return options.inverse(this);
        }
    });
    Handlebars.registerPartial('breakpoint-condition-template', $('#breakpoint-condition-template').html() );
    Handlebars.registerPartial('breakpoint-action-template', $('#breakpoint-action-template').html() );
    Handlebars.registerPartial('breakpoint-right-click-template', $('#breakpoint-right-click-template').html() );
    this.templates = {
        fileTab: Handlebars.compile( $('#file-tab-template').html() ),
        navTab: Handlebars.compile( $('#nav-tab-template').html() ),
        navPane: Handlebars.compile( $('#nav-pane-template').html() ),
        watchedExpression: Handlebars.compile( $('#watched-expr-template').html() ),
        currentSubAndArgs: Handlebars.compile( $('#current-sub-and-args-template').html() ),
        breakpointRightClickMenu: Handlebars.compile( $('#breakpoint-right-click-template').html() ),
        breakpointCondition: Handlebars.compile( $('#breakpoint-condition-template').html() ),
        breakpointAction: Handlebars.compile( $('#breakpoint-action-template').html() ),
        breakpointListItem: Handlebars.compile( $('#breakpoint-list-item-template').html() ),
        forkedChildModal: Handlebars.compile($('#forked-child-modal-template').html() ),
        saveLoadBreakpointsModal: Handlebars.compile($('#save-load-breakpoints-modal-template').html() ),
        programTerminatedModal: Handlebars.compile($('#program-terminated-modal-template').html() ),
        subPickerTemplate: Handlebars.compile($('#sub-picker-template').html() ),
        traceDiffModal: Handlebars.compile($('#trace-diff-modal-template').html() )
    };

    // The step in, over, run buttons
    var $control_buttons = this.$control_buttons = $('.control-button').attr('disabled',true);

    this.restInterface = new RestInterface('');

    // For these breakpoint/action functions, this is a codePane element
    var breakpointChangedForCodePane, breakpointRemovedForCodePane,
        actionChangedForCodePane, actionRemovedForCodePane;
    (function() {
        function itemChangedMaker(bptype) {
            var unconditional_class = bptype,
                conditional_class = 'conditional-'+bptype,
                inactive_class = 'inactive-'+bptype;

            return function(bp) {
                var line = bp.line,
                    $lineElt = this.find('.code-line:nth-child('+line+')');

                if (bp.code === '1') {
                    $lineElt.removeClass(conditional_class).addClass(unconditional_class);
                } else {
                    $lineElt.removeClass(unconditional_class).addClass(conditional_class);
                }
                if (bp.inactive) {
                    $lineElt.addClass(inactive_class);
                } else {
                    $lineElt.removeClass(inactive_class);
                }
            }
        }
        breakpointChangedForCodePane = itemChangedMaker('breakpoint');
        actionChangedForCodePane = itemChangedMaker('bpaction');

        function itemRemovedMaker(bptype) {
            var class_list = bptype + ' '
                            + 'conditional-'+bptype + ' '
                            + 'inactive-'+bptype;

            return function(line) {
                var $lineElt = this.find('.code-line:nth-child('+line+')');
                $lineElt.removeClass(class_list);
            }
        }
        breakpointRemovedForCodePane = itemRemovedMaker('breakpoint');
        actionRemovedForCodePane = itemRemovedMaker('bpaction');
    })();

    this.stackFrameChanged = function(frame_obj, old_frameno, new_frameno) {
        var $tabs = this.stackDiv.find('ul.nav'),
            $tab = $tabs.find('#tab-' + frame_obj.uuid),
            $panes = this.stackDiv.find('div.tab-content'),
            $codePane = $panes.find('#pane-' + frame_obj.uuid);

        var insertStackFrameForLevel = function($tab_elt, $pane_elt, frameno) {
            var mapper = function(a) { return [ a, a.getAttribute('data-frameno') ]; },
                sorter = function(a,b) { return ( a[1] - b[1] ) },
                unmapper = function(a) { return a[0] },
                tab_elts_in_frame_order = $tabs.children().get().map(mapper).sort(sorter).map(unmapper),
                pane_elts_in_frame_order = $panes.children().get().map(mapper).sort(sorter).map(unmapper),
                elt_frameno = $tab_elt.attr('data-frameno'),
                i;

            if (tab_elts_in_frame_order.length == 0
                || frameno > tab_elts_in_frame_order[ tab_elts_in_frame_order.length - 1].getAttribute('data-frameno')
            ) {
                // This new one goes after the last one
                $tabs.append($tab_elt);
                $panes.append($pane_elt);
            } else {
                for(i = 0; i < tab_elts_in_frame_order.length; i++) {
                    if (elt_frameno < tab_elts_in_frame_order[i].getAttribute('data-frameno')) {
                        $tab_elt.insertBefore(tab_elts_in_frame_order[i]);
                        $pane_elt.insertBefore(pane_elts_in_frame_order[i]);
                        break;
                    }
                }
            }
        };

        var frame_deleted = false;
        if (new_frameno === undefined) {
            // a frame got removed
            $tab.remove();
            $codePane.remove();
            $(document).trigger('codePaneRemoved', $codePane);
            frame_deleted = true;

        } else if (old_frameno == undefined) {
            // This is a brand new frame
            $tab = $( this.templates.navTab({
                        uuid: frame_obj.uuid,
                        frameno: new_frameno,
                        longlabel: frame_obj.subroutine,
                        label: frame_obj.subname,
                        filename: frame_obj.filename,
                        lineno: frame_obj.line,
                        wantarray: frame_obj.sigil,
                        active: $tabs.children().length == 0
                    }));
            $tab.find('a[rel="tooltip"]').tooltip();

            $codePane = $( this.templates.navPane({
                                uuid: frame_obj.uuid,
                                frameno: new_frameno,
                                filename: frame_obj.filename,
                                active: $panes.children().length == 0
                        }));

            insertStackFrameForLevel($tab, $codePane, new_frameno);

            this.fileManager.loadFile(frame_obj.filename)
                .done(function($codeTableElt) {
                    var $copy = $codeTableElt.clone();
                    $codePane.find('.program-code-container').append($copy);

                    dbg.setCurrentLineForCodeTable($copy, frame_obj.line);

                    var subArgs = [];
                    for ( var i = 0; i < frame_obj.args.length; i++) {
                        subArgs.push(('render' in frame_obj.args[i]) ? frame.args[i].render('condensed') : frame_obj.args[i]);
                    }
                    $codePane.find('.current-sub-and-args')
                        .append( dbg.templates.currentSubAndArgs({ subroutine: frame_obj.subname, subArgs: subArgs }));

                    $codePane.on('breakpointChanged', breakpointChangedForCodePane)
                             .on('breakpointRemoved', breakpointRemovedForCodePane)
                             .on('actionChanged', actionChangedForCodePane)
                             .on('actionRemoved', actionRemovedForCodePane);

                    $(document).trigger('codePaneAdded', $copy);
                });

        } else {
            // This frame existed before

            if (old_frameno != new_frameno) {
                // It changed levels
                $tab.detach();
                $tab.attr('data-frameno', new_frameno);
                $codePane.detach();
                $codePane.attr('data-frameno', new_frameno);
                insertStackFrameForLevel($tab, $codePane, new_frameno);
            }

            // TODO: only change the tab's title if the line changed
            // update the tab tooltip
            var title = $tab.prop('title');
            title.replace(/\d+$/, frame_obj.line);
            $tab.prop('title', title);

            // Update the line in the code pane
            var codeTable = $codePane.find('.program-code');
            this.setCurrentLineForCodeTable(codeTable, frame_obj.line);
        }

        if ((new_frameno == 0) && ( ! frame_deleted)) {
            //$tab.tab('show');  // Not sure why this doesn't work?
            $tab.find('a').trigger('click');
        }
    };

    var _scrollCodeTableLineIntoView = function(codeTable, line) {
        var activeLine = codeTable.find('.code-line:nth-child('+line+')');

        if (activeLine.length === 0) {
            // Bad info.  This can happen when the program terminates, line is
            // 0 and activeLine.length === 0
            return;
        }

        // Find out if it's visible
        var container = codeTable.closest('div.managed-height');
        var containerTop = container.offset().top;
        var containerBottom = containerTop + container.height();

        var elemTop = activeLine.offset().top;
        var elemBottom = elemTop + activeLine.height();

        var isVisible = ((elemBottom >= containerTop) && (elemTop <= containerBottom)
                        && (elemBottom <= containerBottom) &&  (elemTop >= containerTop) );
        if (!isVisible) {
            //var overShoot = (elemBottom < containerTop) ? -4 : 4;
            // Make it the 4th line from the top
            var overShoot = -4;
            container.scrollTo(activeLine, { over: overShoot });
        }
        return activeLine;
    };

    // Set the given line "active" (hightlited) and scroll it into view
    // if necessary
    this.setCurrentLineForCodeTable = function(codeTable, line) {
        codeTable.find('.active').removeClass('active');
        var activeLine = codeTable.find('.code-line:nth-child('+line+')').addClass('active');

        var scrollCodeTable = function() {
            _scrollCodeTableLineIntoView(codeTable, line);
        };

        var codeTableTabPane = codeTable.closest('.tab-pane');
        if (codeTableTabPane.hasClass('active')) {
            // this is the currently active tab, scroll it now
            scrollCodeTable();
        } else {
            // Not the active tab - arrange for it to scroll the first time it becomes active
            var stackId = codeTableTabPane.attr('id'),
                relatedTab = $('#stack-tabs a[href="#'+stackId+'"]'),
                autoScrollOnce = true;
            relatedTab.on('shown', function(e) {
                // relatedTarget is true when the anchor was actually clicked?
                // seems to be undefined during mouseover of the anchor
                if (autoScrollOnce && e.relatedTarget) {
                    scrollCodeTable();
                    autoScrollOnce = false;
                }
            });
        }
    };

    this.run = function() {

    };

    this.controlButtonClicked = function(e) {
        e.preventDefault();

        $control_buttons.attr('disabled', true);

        var button_action = $(e.currentTarget).attr('data-action'),
            rest_method = this.restInterface[button_action],
            d;
        if (rest_method) {
            d = rest_method.call(this.restInterface);
            d.done(this.handleControlButtonResponse.bind(this));
        }
    };

    this.handleControlButtonResponse = function(response) {
        var events = [];
        if (response.events) {
            events = response.events.map(function(event) {
                return new ProgramEvent(event);
            });
        }

        this.stackManager.update()
            .progress(this.stackFrameChanged.bind(this))
            .done(function() { $control_buttons.attr('disabled', false); });

        events.forEach(this.processProgramEvent, this);
    };

    this.processProgramEvent = function(event) {

    };

    // Initialization
    this.restInterface.programName()
        .done(function(program_name) {
            $elt.find('li#program-name a').html(program_name);
            dbg.programName = name;
        });

    $elt.on('click', '.control-button[disabled!="disabled"]', this.controlButtonClicked.bind(this));

    this.fileManager = new FileManager(this.restInterface);

    this.stackManager = new StackManager(this.restInterface);
    this.stackManager.initialize()
        .progress(this.stackFrameChanged.bind(this))
        .done(function() {
            $control_buttons.attr('disabled', false);
        });
}
