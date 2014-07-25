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
        currentSubAndArgs: Handlebars.compile( $('#current-sub-and-args-template').html() ),
        breakpointRightClickMenu: Handlebars.compile( $('#breakpoint-right-click-template').html() ),
        breakpointCondition: Handlebars.compile( $('#breakpoint-condition-template').html() ),
        breakpointAction: Handlebars.compile( $('#breakpoint-action-template').html() ),
        breakpointListItem: Handlebars.compile( $('#breakpoint-list-item-template').html() ),
        saveLoadBreakpointsModal: Handlebars.compile($('#save-load-breakpoints-modal-template').html() ),
        subPickerTemplate: Handlebars.compile($('#sub-picker-template').html() ),
    };

    // The step in, over, run buttons
    var $control_buttons = this.$control_buttons = $('.control-button').attr('disabled',true);

    var restInterface = this.restInterface = new RestInterface('');

    function whenStackTabIsShown($elt, cb) {
        var stackId = $elt.attr('id'),
            relatedTab = $('#stack-tabs a[href="#'+stackId+'"]');
        relatedTab.one('shown', function(e) {
            // relatedTarget is true when the anchor was actually clicked?
            // seems to be undefined during mouseover of the anchor
            if (e.relatedTarget) {
                cb();
            }
        });
    }

    // Called for each .managed-height element when the window resizes
    // Set the height so the the bottom of the element is the bottom of the
    // window.  This makes the scroll bar work for that element
    function setElementHeight() {
        var $elt = $(this);
        if ($elt.hasClass('program-code-container') && $elt.attr('hidden')) {
            whenStackTabIsShown(setElementHeight.bind(this));
        }
        // this here is the jQuery element to set the height on

        // setting the element's height does not account for any padding
        // .css('padding-top') returns a string like "14px", so we need to slice off
        // the last 2 chars
        var padding = parseInt( $elt.css('padding-top').slice(0, -2))
                        +
                      parseInt( $elt.css('padding-bottom').slice(0, -2));
        $elt.css({'height': (($(window).height())-$elt.offset().top)-padding+'px'});
    };

    this.stackFrameChanged = function(frame_obj, old_frameno, new_frameno) {
        var $tabs = this.stackDiv.find('ul.nav'),
            $tab = $tabs.find('#tab-' + frame_obj.uuid),
            $panes = this.stackDiv.find('div.tab-content'),
            $codePane = $panes.find('#pane-' + frame_obj.uuid);

        var insertStackFrameForLevel = function($tab_elt, $pane_elt) {
            var mapper = function(a) { return [ a, a.getAttribute('data-frameno') ]; },
                sorter = function(a,b) { return ( a[1] - b[1] ) },
                unmapper = function(a) { return a[0] },
                tab_elts_in_frame_order = $tabs.children().get().map(mapper).sort(sorter).map(unmapper),
                pane_elts_in_frame_order = $panes.children().get().map(mapper).sort(sorter).map(unmapper),
                elt_frameno = $tab_elt.attr('data-frameno'),
                i;

            if (tab_elts_in_frame_order.length == 0
                || elt_frameno > tab_elts_in_frame_order[ tab_elts_in_frame_order.length - 1].getAttribute('data-frameno')
            ) {
                // This new one goes after the last one
                $tabs.append($tab_elt);
                $panes.append($pane_elt);
            } else {
                for(i = 0; i < tab_elts_in_frame_order.length; i++) {
                    if (elt_frameno <= tab_elts_in_frame_order[i].getAttribute('data-frameno')) {
                        $tab_elt.insertBefore(tab_elts_in_frame_order[i]);
                        $pane_elt.insertBefore(pane_elts_in_frame_order[i]);
                        break;
                    }
                }
            }
        };

        if (new_frameno === undefined) {
            // a frame got removed
            $tab.remove();
            $codePane.remove();
            $(document).trigger('codePaneRemoved', $codePane);

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

            setElementHeight.call($codePane.find('.managed-height'));

            insertStackFrameForLevel($tab, $codePane);

            this.fileManager.loadFile(frame_obj.filename)
                .done(function($codeTableElt) {
                    var $copy = $codeTableElt.clone();
                    $codePane.find('.program-code-container').append($copy);

                    setCurrentLineForCodeTable($copy, frame_obj.line);

                    var subArgs = [];
                    for ( var i = 0; i < frame_obj.args.length; i++) {
                        subArgs.push(('render' in frame_obj.args[i]) ? frame.args[i].render('condensed') : frame_obj.args[i]);
                    }
                    $codePane.find('.current-sub-and-args')
                        .append( dbg.templates.currentSubAndArgs({ subroutine: frame_obj.subname, subArgs: subArgs }));
                });

        } else {
            // This frame existed before

            if (old_frameno != new_frameno) {
                // It changed levels
                $tab.detach();
                $tab.attr('data-frameno', new_frameno);
                $codePane.detach();
                $codePane.attr('data-frameno', new_frameno);
                insertStackFrameForLevel($tab, $codePane);
            }

            // TODO: only change the tab's title if the line changed
            // update the tab tooltip
            var title = $tab.prop('title');
            title.replace(/\d+$/, frame_obj.line);
            $tab.prop('title', title);

            // Update the line in the code pane
            var codeTable = $codePane.find('.program-code');
            setCurrentLineForCodeTable(codeTable, frame_obj.line);
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
    setCurrentLineForCodeTable = function(codeTable, line) {
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
            whenStackTabIsShown(codeTableTabPane, scrollCodeTable);
        }
    };

    function setCurrentLineForCodeTableEvent(e) {
        var $codeTable = $(e.currentTarget).siblings('.program-code-container').find('.program-code'),
            currentLine = $codeTable.find('.code-line.active').attr('data-lineno');
        setCurrentLineForCodeTable($codeTable, currentLine);
    }


    this.run = function() {

    };

    // This function is called after each control button has returned control
    // to us (step, run, etc).  The stack tabs will already be updated, but
    // enything else that needs updated goes in here.
    function done_after_stack_update() {
        $control_buttons.attr('disabled', false);
        $('#stack-tabs a:first').trigger('click');
        this.watchedExpressionManager.updateExpressions();
    }

    function notifyProgramHasCompletelyExited() {
        $control_buttons.attr('disabled', true);
        restInterface.disconnect();
        $('<span class=alert>Debugged program has exited</span>')
            .appendTo('#controls');
        alert('Debugged program has exited');
    }

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
            .done( done_after_stack_update.bind(this) );

        events.forEach(function(event) {
            event.render($elt)
                 .done(function(button) {
                    if (button == 'exit') {
                        restInterface.exit()
                                     .done(notifyProgramHasCompletelyExited);
                    }
                });
        });
    };

    // Called by popoverPerlVar to draw the resulting data
    var $perlVarPopover = undefined;
    function drawPerlPopover(data) {
        var perl_value = PerlValue.parseFromEval(data),
            popover_args;

        if (! $perlVarPopover) {
            return;
        }

        popover_args = {  trigger: 'manual',
                        placement: 'bottom',
                        html: true,
                        container: $elt,
                        content: perl_value.renderValue()
                    };
        var header = perl_value.renderHeader();
        if (header && (header.length > 0)) {
            popover_args.title = header;
        }
        $perlVarPopover.popover(popover_args)
                       .popover('show');
    }

    // Event for when the user hovers over a perl variable in the code
    function popoverPerlVar(e) {
        var $elt = $(e.currentTarget),
            eval = $elt.attr('data-eval'),
            stack_level = $elt.closest('.tab-pane').attr('data-frameno'),
            timer = $elt.data('timerid');

        if (timer != null) {
            // mouseout before the timer fired - remove the timer
            window.clearTimeout(timer);
        }

        // Remove any previous hover var elements
        $('.hovered-perl-var').removeClass('hovered-perl-var');
        if ($perlVarPopover) {
            $perlVarPopover.popover('destroy');
        }

        $elt.addClass('hovered-perl-var');
        // Is this an indexed part of a variable
        var also = $elt.attr('data-part-of');
        if (also) {
            // hilite it, too
            $elt.parent().find('[data-eval="'+also+'"]').addClass('hovered-perl-var');
        }
        $perlVarPopover = $elt;

        var timer = window.setTimeout(function() {
            if ($perlVarPopover) {
                $perlVarPopover.data('timerid', null);

                restInterface.getVarAtLevel(eval, stack_level)
                             .done(drawPerlPopover);
            }
        }, 400);
        $perlVarPopover.data('timerid', timer);
    }

    function removePopoverPerlVar (e) {
        if ($perlVarPopover) {
            $perlVarPopover.popover('destroy');
            $perlVarPopover = undefined;
        }
    }

    var $lastControlKeyElement = $control_buttons.filter('[data-action="stepin"]');
    function setKeybindings() {
        // Seems that divs can't receive key events, so we can't bind the
        // handler to this.elt :(
        $(document).keypress(function(e) {
            if (! $(e.target).is('body')) {
                // Don't handle events for elements like text inputs
                return;
            }
            if (e.ctrlKey || e.altKey || e.metaKey) {
                // Don't process when these modifier keys are used
                // Shift as a modifier is accounted for in e.which
                return;
            }
            switch (e.which) {
                case 115: //s
                    $lastControlKeyElement = $control_buttons.filter('[data-action="stepin"]')
                            .click();
                    e.stopPropagation();
                    break;
                case 110: // n
                    $lastControlKeyElement = $control_buttons.filter('[data-action="stepover"]')
                        .click();
                    e.stopPropagation();
                    break;
                case 114: // r
                     $control_buttons.filter('[data-action="stepout"]')
                                        .click();
                    e.stopPropagation();
                    break;
                case 99: // c
                    $control_buttons.filter('[data-action="continue"]')
                                        .click();
                    e.stopPropagation();
                    break;
                case 113: // q
                    control_buttons.filter('[data-action="exit"]')
                                        .click();
                    e.stopPropagation();
                    break;
                case 13:  // cr
                    $lastControlKeyElement.click();
                    e.stopPropagation();
                    break;
                case 120: // x
                    $('#add-watch-expr').click();
                    e.stopPropagation();
                    e.preventDefault();
                    break;
                case 46: // .
                    dbg.stackDiv.find('.tab-pane.active .current-sub-and-args').click();
                    e.stopPropagation();
                    break;
                case 102: // f
                    $('#add-file').click();
                    e.stopPropagation();
                    break;
                case 76: // L
                    $('#breakpoint-container-handle').click();
                    e.stopPropagation();
                    break;
                case 98: //b
                    dbg.stackDiv.find('.tab-pane.active .code-line.active span.lineno').click();
                    e.stopPropagation();
                    break;
            }
        });
    }

    // Initialization
    this.restInterface.programName()
        .done(function(program_name) {
            $elt.find('li#program-name a').html(program_name);
            dbg.programName = name;
        });
    this.fileManager = new FileManager(this.restInterface);

    this.stackManager = new StackManager(this.restInterface);
    this.stackManager.initialize()
        .progress(this.stackFrameChanged.bind(this))
        .done( done_after_stack_update.bind(this) );

    this.breakpointManager = new BreakpointManager(this.$elt, this.restInterface);
    this.watchedExpressionManager = new WatchedExprManager(this.restInterface);

    // Events
    $elt.on('click', '.control-button[disabled!="disabled"]', this.controlButtonClicked.bind(this))
        .on('mouseenter', '.popup-perl-var', popoverPerlVar.bind(this))
        .on('mouseleave', '.popup-perl-var', removePopoverPerlVar.bind(this))
        .on('click', '.current-sub-and-args', setCurrentLineForCodeTableEvent.bind(this));

    setKeybindings();

    $('.managed-height').each(setElementHeight);
    $(window).resize(function() { $('.managed-height').each(setElementHeight) });

    this.breakpointManager.sync();
}
