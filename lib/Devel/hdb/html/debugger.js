function Debugger(sel) {
    var dbg = this;
    this.elt = $(sel);

    this.filewindowDiv = this.elt.find('div#filewindow');
    this.stackDiv = this.elt.find('div#stack');
    this.watchDiv = this.elt.find('div#watch-expressions');

    this.messageHandler = new MessageHandler();

    // keys are filenames, values are jQuery objects for the HTML
    // without breakpoints or active line
    this.fileManager = new FileManager(this.messageHandler);

    this.codePanes = {};  // All the code window panes loaded by filename

    // keys are filenames then line number.  Value is the breakpoint object
    this.breakpointManager = new BreakpointManager();
    this.breakpointPopover = undefined;  // Which line $elt has the popover open

    this.perlVarPopover = undefined; // Whick span $elt has the popover open

    // Keys are expression strings, values are the div they display in
    this.watchedExpressions = {};

    this.programTerminated = false;

    // templates
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navTabContentTemplate = Handlebars.compile( $('#nav-tab-content-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );
    this.watchedExpressionTemplate = Handlebars.compile( $('#watched-expr-template').html() );
    this.currentSubAndArgsTemplate = Handlebars.compile( $('#current-sub-and-args-template').html() );
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
    this.breakpointRightClickMenuTemplate = Handlebars.compile( $('#breakpoint-right-click-template').html() );
    this.breakpointConditionTemplate = Handlebars.compile( $('#breakpoint-condition-template').html() );
    this.breakpointActionTemplate = Handlebars.compile( $('#breakpoint-action-template').html() );
    this.breakpointListItemTemplate = Handlebars.compile( $('#breakpoint-list-item-template').html() );
    this.forkedChildModalTemplate = Handlebars.compile($('#forked-child-modal-template').html() );
    this.saveLoadBreakpointsModalTemplate = Handlebars.compile($('#save-load-breakpoints-modal-template').html() );

    // The step in, over, run buttons
    this.controlButtons = $('.control-button');

    this.initialize = function() {
        this.messageHandler.addHandler('program_name', this.programNameUpdated.bind(this))
                            .addHandler('termination', this.programWasTerminated.bind(this))
                            .addHandler('evalresult', this.watchExpressionResult.bind(this))
                            .addHandler('hangup', this.hangup.bind(this))
                            .addHandler('getvar', this.drawPerlVarPopover.bind(this))
                            .addHandler('child_process', this.childProcessForked.bind(this));


        this.getProgramName();
        this.getStack();

        // Remove the breakpoint popover if the user clicks outside it
        this.elt.click(function(e) {
            if (dbg.breakpointPopover && ($(e.target).closest('.popover').length === 0)) {
                e.preventDefault();
                e.stopPropagation();
                dbg.breakpointPopover.popover('destroy');
                dbg.breakpointPopover = undefined;
            }
        });
        this.elt.on('click', '.control-button', this.controlButtonClicked.bind(this));

        // events for breakpoints
        this.elt.on('click', '.code-line:not(.unbreakable) .lineno',
                    this.breakableLineClicked.bind(this));
        this.elt.on('contextmenu', '.code-line:not(.unbreakable) .lineno',
                    this.breakableLineRightClicked.bind(this));
        this.elt.on('click', '.breakpoint-condition,.action',
                    this.editBreakpointCondition.bind(this));
        this.elt.on('change', '.toggle-breakpoint,.toggle-action',
                    this.toggleBreakpointOrAction.bind(this));
        this.elt.on('click', '.remove-breakpoint',
                    this.removeBreakpointFromList.bind(this));
        this.elt.on('click', '.breakpoint-goto',
                    this.scrollToBreakpoint.bind(this));
        this.elt.on('hover', '.popup-perl-var',
                    this.popoverPerlVar.bind(this));
        this.elt.on('click', '.save-load-breakpoints',
                    this.saveLoadBreakpoints.bind(this));

        $('#breakpoint-container-handle').click(function(e) {
            var breakpointPane = $('#breakpoint-container'),
                icon = $('#breakpoint-container-handle-icon');
            if (breakpointPane.hasClass('extended')) {
                breakpointPane.animate(
                    { width: 0 },
                    'fast',
                    function() {
                        breakpointPane.removeClass('extended');
                        icon.removeClass('icon-chevron-left').addClass('icon-chevron-right');
                    });
            } else {
                breakpointPane.addClass('extended');
                breakpointPane.animate(
                    { width: $('#side-tray').width() },
                    'fast',
                    function() {
                        icon.removeClass('icon-chevron-right').addClass('icon-chevron-left');
                    });
            }
        });

        this.elt.on('click', '.current-sub-and-args', function(e) {
            var codeTable = $(e.currentTarget).parent().find('.program-code'),
                activeLine = codeTable.find('.active'),
                activeLineno = parseInt(activeLine.attr('data-lineno'));

            dbg.setCurrentLineForCodeTable(codeTable, activeLineno);

        });

        this.watchDiv.on('click', '.remove-watched-expression',
                    this.removeWatchExpression.bind(this));
        this.watchDiv.on('click', '.expr-collapse-button',
                    this.toggleCollapseWatchExpression.bind(this));
        this.watchDiv.on('dblclick', '.expr',
                    this.addEditWatchExpression.bind(this));
        this.watchDiv.on('click', '#add-watch-expr',
                    this.addEditWatchExpression.bind(this));

        $('.managed-height').each(this._setElementHeight);
        $(window).resize(function() { $('.managed-height').each(dbg._setElementHeight) });

        // These two callbacks handle resizing the code/watch division
        var dragging = false;
        $(document).on('mousedown', '#drag-divider', function(e) {
            e.preventDefault();
            dragging = true;
            var divider = $('#drag-divider'),
                dividerOffset = divider.offset(),
                ghostDivider = $('<div id="ghost-divider">')
                                .css({
                                    height: divider.outerHeight(),
                                    top: dividerOffset.top,
                                    left: dividerOffset.left
                                })
                                .appendTo('body');
            $(document).mousemove(function(e) {
                var controls = $('#controls'),
                    minLeft = controls.offset().left + controls.width();
                if (e.pageX <= minLeft) {
                    // Don't let it get smaller than the control buttons width
                    return;
                }
                ghostDivider.css('left', e.pageX+2);
            });
        });
        $(document).mouseup(function(e) {
            if (dragging) {
                var ghostDivider = $('#ghost-divider'),
                    width = $(window).width() - ghostDivider.offset().left;
                $('#columnator').css('padding-right', width);
                $('#drag-divider').next()
                            .css({  width: width-1,
                                    'margin-right': 0-width });
                ghostDivider.remove();
                $(document).unbind('mousemove');
                dragging = false;
            }
        });

        this.stackManager = new StackManager(this.messageHandler, this.stackFrameChanged.bind(this));

        return this;
    };

    // Set the height so the the bottom of the element is the bottom of the
    // window.  This makes the scroll bar work for that element
    this._setElementHeight = function() {
        // this here is the jQuery element to set the height on

        // setting the element's height does not account for any padding
        // .css('padding-top') returns a string like "14px", so we need to slice off
        // the last 2 chars
        var padding = parseInt( $(this).css('padding-top').slice(0, -2))
                        +
                      parseInt( $(this).css('padding-bottom').slice(0, -2));
        $(this).css({'height': (($(window).height())-$(this).offset().top)-padding+'px'});
    };

    this.programWasTerminated = function(data) {
        alert('Debugged program terminated with exit code '+data.exit_code);
        this.controlButtons.attr('disabled','true');
        this.controlButtons.filter('#exit').removeAttr('disabled');
        this.programTerminated = true;
    };
    this.hangup = function(message) {
        var alertMsg = 'Debugged program exited';
        if (message) {
            alertMsg = alertMsg + ': ' + message;
        }
        alert(alertMsg);
        this.controlButtons.attr('disabled','true');
        this.programTerminated = true;
    };

    this._defaultBreakpointFileName = function () {
        return this.programName + '.hdb';
    };
    this.saveLoadBreakpoints = function(e) {
        e.preventDefault();
        var isSave = $(e.currentTarget).attr('id') === 'save-breakpoints';
        var modal = $( this.saveLoadBreakpointsModalTemplate({
                                    action: isSave ? 'Save' : 'Load',
                                    filename: this._defaultBreakpointFileName()
                        }))
                        .appendTo(this.elt)
                        .modal({ backdrop: true, keyboard: true, show: true })
                        .focus();

        modal.on('hidden', function(e) {
            modal.remove();
        });

        var form = modal.find('form'),
            messageHandler = this.messageHandler;
        form.submit(function(e) {
            e.preventDefault();
            var savefile = form.find('[name="filename"]').val();
            messageHandler.ajaxSession(
                   {url: isSave ? 'saveconfig' : 'loadconfig',
                    type: 'POST',
                    dataType: 'json',
                    data: { f: savefile },
                },
                function(data) {
                    modal.modal('hide');
                    messageHandler.sessionDone();
                }
            );
        });
    };

    // Toggle the breakpoint on a line
    this.breakableLineClicked = function(e) {
        var $elt = $(e.target),
            filename = $elt.closest('.program-code').attr('data-filename'),
            lineno = $elt.closest('.code-line').attr('data-lineno'),
            bp = this.breakpointManager.get(filename, lineno),
            requestData = { f: filename, l: lineno };

        requestData.c = bp.condition ? '' : 1;  // toggle

        $.ajax({url: 'breakpoint',
                type: 'POST',
                dataType: 'json',
                data: requestData,
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    };

    // Triggered by the breakpoint manager whenever a breakpoint changes
    // Update the breakpoint pane list
    this.updateBreakpointList = function(filename, bp_hash) {
        var breakpointsList = $('#breakpoints-list'),
            breakpointListItem,
            bpFileItems = breakpointsList.children(),
            bpFileItem = breakpointsList.find('[data-filename="'+filename+'"] ol'),
            isDeleteBreakpoint;

        for (line in bp_hash) {
            isDeleteBreakpoint = ! (bp_hash[line].condition || bp_hash[line].action);

            breakpointListItem = breakpointsList.find('[data-filename="' + filename
                                                        + '"][data-lineno="' + line + '"]'),
            newBpListItem = $(dbg.breakpointListItemTemplate(
                                    $.extend({filename : filename, lineno: line}, bp_hash[line])));

            if (isDeleteBreakpoint && breakpointListItem.length) {
                breakpointListItem.remove();

            } else if (breakpointListItem.length) {
                // already exists
                breakpointListItem.empty().html(newBpListItem.html());
            } else {
                // Make it new
                // first, see if we're already listing this file
                var nextFileItem,
                    i;

                if (bpFileItem.length === 0) {
                    // Didn't find this file listed; add this file in the appropriate place
                    for (i = 0; i < bpFileItems.length; i++) {
                        if (bpFileItems[i].attributes.getNamedItem('data-filename').value > filename) {
                            nextFileItem = bpFileItems[i];
                            break;
                        }
                    }
                    if (nextFileItem) {
                        bpFileItem = $('<li data-filename="'+filename+'"><span><small>'
                                                +filename+'</small></span><ol></ol></li>')
                                        .insertBefore(nextFileItem);
                    } else {
                        bpFileItem = $('<li data-filename="'+filename+'"><span><small>'
                                                +filename+'</small></span><ol></ol></li>')
                                        .appendTo(breakpointsList);
                    }
                    // Since it's a new filename, we can immediately this
                    // breakpoint to the empty list item
                    bpFileItem = bpFileItem.children('ol'); // The list inside this list item
                    bpFileItem.append(newBpListItem);

                } else {
                    // The file is already listed. Insert the new breakpoint into the
                    // list at the appropriate place
                    var bpLineItems = bpFileItem.children(),
                        nextBpLineItem;

                    for (i = 0; i < bpLineItems.length; i++) {
                        if (parseInt(bpLineItems[i].attributes.getNamedItem('data-lineno').value) > line) {
                            nextBpLineItem = bpLineItems[i];
                            break;
                        }
                    }
                    if (nextBpLineItem) {
                        newBpListItem.insertBefore(nextBpLineItem);
                    } else {
                        newBpListItem.appendTo(bpFileItem);
                    }
                }
            }
        }
    };
    // Triggered by the breakpoint manager whenever a breakpoint changes
    // Update the line-number icons for this breakpoint
    this.breakpointsForPane = function(e, bp_hash) {
        // bp_hash is a hash of { line: { condition: cond, action: act } }
        // 'this' in this function is the .program-code table with the program code

        var $codeTable = $( this ),
            filename = $codeTable.attr('data-filename'),
            line;

        for (line in bp_hash) {
            var condition = bp_hash[line].condition,
                conditionEnabled = bp_hash[line].conditionEnabled,
                action = bp_hash[line].action,
                lineElt = $codeTable.find('.code-line:nth-child('+line+')');

            lineElt.removeClass('breakpoint conditional-breakpoint inactive-breakpoint bpaction');
            if (condition) {
                if (condition === '1') {
                    lineElt.addClass('breakpoint');
                } else {
                    lineElt.addClass('conditional-breakpoint');
                }
                if (! conditionEnabled) {
                    lineElt.addClass('inactive-breakpoint');
                }
            }
            if (action) {
                lineElt.addClass('bpaction');
            }
        }
    };

    // Context menu for breakpoints
    this.breakableLineRightClicked = function(e) {
        var $elt = $(e.target);

        e.preventDefault();
        this._drawBreakpointRightClickMenu($elt);
    };
    this._drawBreakpointRightClickMenu = function($elt) {
        var filename = $elt.closest('[data-filename]').attr('data-filename'),
            lineno = $elt.closest('[data-lineno]').attr('data-lineno'),
            bp = this.breakpointManager.get(filename, lineno),
            menu;

        $.extend(bp, { filename: filename, lineno: lineno });
        menu = this.breakpointRightClickMenuTemplate($.extend({ filename: filename, lineno: lineno }, bp));

        if (this.breakpointPopover) {
            this.breakpointPopover.popover('destroy');
        }
        this.breakpointPopover = $elt.popover({ html: true,
                                                trigger: 'manual',
                                                placement: 'right',
                                                title: filename + ': ' + lineno,
                                                container: dbg.elt,
                                                content: menu})
                                        .popover('show');
    };

    // When the user clicks the checkbox next to a breakpoint condition or action
    this.toggleBreakpointOrAction = function(e) {
        var $elt = $(e.currentTarget),
            filename = $elt.closest('[data-filename]').attr('data-filename'),
            lineno = $elt.closest('[data-lineno]').attr('data-lineno'),
            type = $elt.hasClass('toggle-breakpoint') ? 'condition' : 'action',
            state = $elt.is(':checked'),
            requestData = { f: filename, l: lineno };

        if (type === 'condition') {
            // ci means condition inactive, so we need to flip the state value to send
            requestData.ci = state ? 0 : 1;
        } else {
            requestData.ai = state ? 0 : 1;
        }

        $.ajax({url: 'breakpoint',
                type: 'POST',
                dataType: 'json',
                data: requestData,
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    };

    // When the user clicks the X to remove an item from the breakpoint list
    this.removeBreakpointFromList = function(e) {
        var $elt = $(e.currentTarget),
            filename = $elt.closest('[data-filename]').attr('data-filename'),
            lineno = $elt.closest('[data-lineno]').attr('data-lineno');

        $.ajax({url: 'breakpoint',
                type: 'POST',
                dataType: 'json',
                data: { f: filename, l: lineno, c: '', a: '' },
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    };

    // Called when the user clicks the swoopy aarow next to a breakpoint location
    // in the breakpoint pane list
    this.scrollToBreakpoint = function(e) {
        var $elt = $(e.currentTarget),
            filename = $elt.closest('[data-filename]').attr('data-filename'),
            lineno = $elt.closest('[data-lineno]').attr('data-lineno'),
            codeTable = this.elt.find('.program-code[data-filename="'+filename+'"]').first();

        var lineElt = this._scrollCodeTableLineIntoView(codeTable, lineno);
        var originalBg = lineElt.css('background-color');
        lineElt.css({ 'background-color': 'yellow'});
        setTimeout(function() { lineElt.css({'background-color': originalBg}) }, 1000);
    };

    // When the user clicks a breakpoint condition or action in the
    // breakpoint context menu or breakpoint pane list
    this.editBreakpointCondition = function (e) {
        var $elt = $(e.currentTarget),
            filename = $elt.closest('[data-filename]').attr('data-filename'),
            lineno = $elt.closest('[data-lineno]').attr('data-lineno'),
            type = $elt.hasClass('breakpoint-condition') ? 'condition' : 'action',
            dbg = this;

        e.stopPropagation();  // Keep the popover from disappearing from the click watcher
        $elt.empty()
            .append('<form><input class="span2" type="text" name="input" placeholder="'+type+'" autofocus="true"></form>')
            .submit(function(e) {
                var form = e.target,
                    value = form.elements['input'].value;

                e.preventDefault();
                if (type === 'condition') {
                    dbg.breakpointManager.set({ filename: filename, lineno: lineno, condition: value});

                } else if (type === 'action') {
                    dbg.breakpointManager.set({ filename: filename, lineno: lineno, action: value});
                }
                if (dbg.breakpointPopover && ($elt.closest('.popover-content').length !== 0)) {
                    // It was part of the right-click breakpoint menu
                    dbg._drawBreakpointRightClickMenu(dbg.breakpointPopover);
                }
            });
    };

    this.getStack = function() {
        $.ajax({url: 'stack',
            dataType: 'json',
            type: 'GET',
            success: this.messageHandler.consumer,
            error: this.ajaxError
        });
    };
    this.getAllBreakpoints = function(filename) {
        var params = {};
        if (filename !== undefined) {
            params.filename = filename;
        }

        $.ajax({url: 'breakpoints',
                dataType: 'json',
                type: 'GET',
                data: params,
                success: this.messageHandler.consumer,
                error: this.ajaxerror
        });
    };

    this.controlButtonClicked = function(e) {
        e.preventDefault();
        if ($(e.target).attr('disabled')) {
            return;
        }
        dbg.controlButtons.attr('disabled','true');

        var buttonId = $(e.currentTarget).attr('id');

        $.ajax({url: buttonId,
                type: 'GET',
                dataType: 'json',
                success: function(messages) {
                    dbg.messageHandler.consumer(messages);
                    dbg.refreshAllWatchExpressions();
                    if (! dbg.programTerminated) {
                        dbg.controlButtons.removeAttr('disabled');
                    }
                },
                error: this.ajaxError
            });
     };

    this.run = function() {

    };

    // Event for when the user hovers over a perl variable in the code
    this.popoverPerlVar = function(e) {
        var $elt = $(e.currentTarget),
            eval = $elt.attr('data-eval'),
            stackLevelTag = $elt.closest('.tab-pane').attr('id'),
            stackLevel = 0,
            dbg = this;

        // Remove any previous hover var elements
        $('.hovered-perl-var').removeClass('hovered-perl-var');
        if (this.perlVarPopover) {
            this.perlVarPopover.popover('destroy');
        }
        if (e.type === 'mouseleave') {
            this.perlVarPopover = undefined;
            return;
        }

        if (stackLevelTag.match(/stack(\d+)/)) {
            stackLevel = parseInt(RegExp.$1);
        }

        $elt.addClass('hovered-perl-var');
        this.perlVarPopover = $elt;
        $.ajax({url: 'getvar',
                dataType: 'json',
                data: { l: stackLevel, v: eval },
                type: 'POST',
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    }
    this.drawPerlVarPopover = function(data) {
        var p,
            popupArgs,
            title;

        if (! this.perlVarPopover) {
            return;
        }

        p = new PerlValue.parseFromEval(data.result);
        popupArgs = {   trigger: 'manual',
                        placement: 'bottom',
                        html: true,
                        container: dbg.elt,
                        content: p.renderValue()
                    };
        title = p.renderHeader();
        if (title && (title.length > 0)) {
            popupArgs.title = title;
        }
        this.perlVarPopover.popover( popupArgs )
                            .popover('show');
    };

    this.programNameUpdated = function(name) {
        this.elt.find('li#program-name a').html(name);
        this.programName = name;
    };
    this.getProgramName = function() {
        $.ajax({url: 'program_name',
                dataType: 'json',
                type: 'GET',
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    };

    // Set the given line "active" (hightlited) and scroll it into view
    // if necessary
    this.setCurrentLineForCodeTable = function(codeTable, line) {
        codeTable.find('.active').removeClass('active');
        var activeLine = codeTable.find('.code-line:nth-child('+line+')').addClass('active');

        this._scrollCodeTableLineIntoView(codeTable, line);
    };

    // Ensure the given line number of the codeTable is visible
    this._scrollCodeTableLineIntoView = function(codeTable, line) {
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
            // If the target element is off the top, leave 2 lines at the top,
            // if it's off the bottom, leave 2 lines at the bottom
            var overShoot = (elemBottom < containerTop) ? -2 : 2;
            container.scrollTo(activeLine, { over: overShoot });
        }
        return activeLine;
    };

    // Called by the stackManager when the given stack frame # has changed from
    // the last time
    this.stackFrameChanged = function(i, frame, isSameFrame) {
        var tabs = this.stackDiv.find('ul.nav'),
            panes = this.stackDiv.find('div.tab-content'),
            tabId = 'stack' + i,
            filename = frame ? frame.filename : '',
            line = frame ? frame.line : -1,
            tab = tabs.find('.stack-tab:nth-child('+ (i+1) +')'),
            codePane = panes.find('.tab-pane:nth-child('+ (i+1) + ')'),
            codeContainer = codePane.find('.program-code-container'),
            dbg = this,
            html = '',
            subArgs = [];

        if (! frame) {
            // Remove a stack frame
            tab.remove();
            codePane.remove();
            return;
        }

        // Update the tab completely so the tooltip text will be correct
        if (tab.length === 0) {
            tab = $( this.navTabTemplate({active: i === 0}) );
            tab.appendTo(tabs);
        }
        html = this.navTabContentTemplate({ label: frame.subname,
                                            longlabel: frame.subroutine,
                                            tabId: tabId,
                                            filename: filename,
                                            lineno: line
                                        });
        tab.html(html);
        tab.find('a[rel="tooltip"]').tooltip();

        var n;
        for (n = 0; n < frame.args.length; n++) {
            subArgs.push(('render' in frame.args[n]) ? frame.args[n].render('condensed') : frame.args[n] );
        }

        if (isSameFrame) {
            // same package and filename for the current frame
            if (i === 0) {
                // just update the currently active line
                var codeTable = codePane.find('.program-code');
                this.setCurrentLineForCodeTable(codeTable, line);

                var current = dbg.currentSubAndArgsTemplate({  subroutine: frame.subroutine,
                                                                lineno: frame.line,
                                                                subArgs: subArgs
                                                            });
                codePane.find('.current-sub-and-args')
                        .empty()
                        .html( current );
            }
            return;
        }

        html = this.navPaneTemplate({   tabId: tabId,
                                        filename: filename,
                                        active: i === 0 });
        if (codePane.length === 0) {
            codePane = $(html).appendTo(panes);
            codeContainer = codePane.find('.program-code-container'),
            dbg._setElementHeight.call(codePane.find('.managed-height'));
        } else {
            codeContainer.empty();
        }
        this.fileManager.loadFile(filename)
            .done(function($elt) {
                var $copy = $elt.clone();

                $copy.appendTo(codeContainer)
                    .bind('breakpoints-updated', dbg.breakpointsForPane);

                // Make the code windows' fonts and spacing 80% of normal
                $copy.css('font-size', '80%');
                // Chop off the "px" from the end of the font-size and convert to int
                var lineHeight = parseInt( $copy.css('line-height').slice(0,-2));
                lineHeight = "" + (lineHeight * 0.8) + "px";
                $copy.css('line-height', lineHeight);

                dbg.setCurrentLineForCodeTable($copy, line);
                dbg.breakpointManager.markBreakpoints(filename, $copy);

                var current = dbg.currentSubAndArgsTemplate({  subroutine: frame.subroutine,
                                                                lineno: frame.line,
                                                                subArgs: subArgs
                                                            });
                codePane.find('.current-sub-and-args')
                        .empty()
                        .html( current );
            });
    };

    this.refreshWatchExpression = function(expr) {
        $.ajax({
            url:'eval',
            type: 'POST',
            dataType: 'json',
            data: expr,
            success: this.messageHandler.consumer,
            error: this.ajaxError
        });
    };
    this.refreshAllWatchExpressions = function() {
        var expr;
        for (expr in this.watchedExpressions) {
            this.refreshWatchExpression(expr);
        }
    };
    this.watchExpressionResult = function(data) {
        var thisDiv = this.watchedExpressions[data.expr],
            p;
        if (thisDiv) {
            if (data.exception) {
                p = new PerlValue.exception(data.exception);
            } else {
                p = PerlValue.parseFromEval(data.result);
            }
            thisDiv.find('.value').empty().append(p.render());
        }
    };
    this.removeWatchExpression = function(e) {
        var div = $(e.target).closest('div.watched-expression'),
            expr = div.attr('data-expr');

        delete this.watchedExpressions[expr];
        div.remove();
    };
    this.toggleCollapseWatchExpression = function(e) {
        var collapsable = $(e.target),
            toCollapse = collapsable.siblings('dl,ul')

        e.preventDefault();
        toCollapse.toggle(100);
    };
    this.addEditWatchExpression = function(e) {
        var newExprInput = $('<input type="text" name="expr" autofocus="1">'),
            newExprForm = $('<form/>').append(newExprInput),
            watchExpressions = this.elt.find('#watch-expressions-container'),
            $target = $(e.target),
            dbg = this,
            originalExpr,
            originalElement;

        e.preventDefault();

        if ($target.hasClass('expr')) {
            // editing an existing expression
            originalExpr = $target.html();
            originalElement = $target.closest('div.watched-expression');
            $target.replaceWith(newExprForm);
            newExprInput.val(originalExpr);
            newExprForm.__revert = function() { this.replaceWith(originalElement) };

        } else {
            //Adding a new expression
            watchExpressions.append(newExprForm);
            newExprForm.__revert = function () { this.remove() };
        }

        newExprForm.submit(function(e) {
            var expr = newExprInput.val();
            expr = expr.replace(/^\s+|\s+$/g,''); // Remove leading and trailing spaces

            e.preventDefault();

            if (expr === originalExpr) {
                newExprForm.__revert();

            } else if (dbg.watchedExpressions[expr]) {
                // Already watching this expr
                newExprForm.__revert();
                alert('Already watching '+expr);

            } else {
                var newExpr = $( dbg.watchedExpressionTemplate({ expr: expr }) );
                dbg.watchedExpressions[expr] = newExpr;
                if (originalExpr) {
                    // Editing a watch expr
                    delete dbg.watchedExpressions[originalExpr];
                    originalElement.replaceWith(newExpr);
                } else {
                    // new watch expr
                    newExprForm.__revert();
                    watchExpressions.append(newExpr);
                }
                dbg.refreshWatchExpression(expr);
            }
        });
    };

    this.ajaxError = function(xhdr, status, error) {
        // debugger;
        alert('Error from ajax call.  Status "' + status +'" error "'
                +error+'": '+xhdr.responseText);
    };

    this.childProcessForked = function(data) {
        var pid = data.pid,
            uri = data.uri,
            run = data.run;

        //alert('Child process '+pid+' forked.  <a href="'+uri+'">Click here</a> to debug it');
        var modal = $( this.forkedChildModalTemplate({pid: pid, uri: uri, run: run}))
                        .appendTo(this.elt)
                        .modal({ backdrop: true, keyboard: true, show: true })
                        .focus();
        modal.on('click', '.btn', function(e) {
            var $elt = $(e.target);
            modal.on('hidden', function(e) {
                modal.remove();
            });
            modal.modal('hide');
            if ($elt.hasClass('run-child')) {
                // telling the child process to run without stopping.  We'll send
                // the request by hand, here
                $.ajax({url: $elt.attr('href'),
                        method: 'GET',
                        error: this.ajaxError
                    });
                e.preventDefault();
            }
            // for the "open" button, go ahead and let the browser follow the link
            // it will open in a new window/tab
        });
    };

    this.initialize();

    function BreakpointManager() {
        this.breakpoints    = {};  // keyed by filename, then by line number
        this.messageHandler = dbg.messageHandler;

        this.breakpointUpdated = function(data) {
            var filename    = data.filename,
                line        = data.lineno,
                condition   = data.condition,
                action      = data.action,
                conditionInactive   = data.condition_inactive,
                actionInactive      = data.action_inactive;

            var breakpoint = {};
            breakpoint[line] = {};

            if (condition) {
                breakpoint[line].condition = condition;
                breakpoint[line].conditionEnabled = ! conditionInactive;
            }
            if (action) {
                breakpoint[line].action = action;
                breakpoint[line].actionEnabled = ! actionInactive;
            }

            if (condition || action) {
                // breakpoint in a new file
                if (! (filename in this.breakpoints)) {
                    this.breakpoints[filename] = {};
                }
                this.breakpoints[filename][line] = breakpoint[line];
            } else if (filename in this.breakpoints) {
                // removing a breakpoint + action
                delete this.breakpoints[filename][line];
            }

            dbg.updateBreakpointList(filename, breakpoint);
            $('.program-code[data-filename="'+filename+'"]')
                .trigger('breakpoints-updated', [ breakpoint ]);
        };

        this.markBreakpoints = function(filename, $elt) {

            if (filename in this.breakpoints) {
                $elt.trigger('breakpoints-updated', this.breakpoints[filename]);
            } else {
                $.ajax({url: 'breakpoints',
                        type: 'GET',
                        data: { f: filename },
                        dataType: 'json',
                        success: this.messageHandler.consumer
                    });
            }
        };
        this.get = function(filename, lineno) {
           if (filename in this.breakpoints) {
                return this.breakpoints[filename][lineno] || {};
            } else {
                return {};
            }
        };
        this.set = function(params) {
            var filename = params.filename,
                lineno = params.lineno,
                postData = { f: filename, l: lineno };

            // Save the condition now in case other parts of the app need to
            // see the change before the browser's event loop gets a chance to
            // process the ajax send and receive the reply
            this.breakpoints[filename] = this.breakpoints[filename] || {};
            this.breakpoints[filename][lineno] = this.breakpoints[filename][lineno] || {};

            if ('condition' in params) {
                this.breakpoints[filename][lineno].condition = params.condition;
                postData.c = params.condition;
                if (! ('conditionEnabled' in params)) {
                    // If enable/disable wasn't given, assume enabled
                    this.breakpoints[filename][lineno].conditionEnabled = true;
                }
            }
            if ('conditionEnabled' in params) {
                this.breakpoints[filename][lineno].conditionEnabled = params.conditionEnabled;
                postData.ci = ! params.conditionEnabled;
            }
            if ('action' in params) {
                this.breakpoints[filename][lineno].action = params.action;
                postData.a = params.action;
                if (! ('actionEnabled' in params)) {
                    // If enable/disable wasn't given, assume enabled
                    this.breakpoints[filename][lineno].actionEnabled = true;
                }
            }
            if ('actionEnabled' in params) {
                this.breakpoints[filename][lineno].actionEnabled = params.actionEnabled;
                postData.ci = ! params.actionEnabled;
            }

            $.ajax({url: 'breakpoint',
                    type: 'POST',
                    data: postData,
                    success: this.messageHandler.consumer
                });
        };

        this.messageHandler.addHandler('breakpoint', this.breakpointUpdated.bind(this))
    };
}

// Routes incoming messages to the right place
function MessageHandler() {
    this.handlers = {};
    this.requestors = {};

    this.req_id = 1;
    this.current_req_id = undefined;

    this.addHandler = function(type, cb) {
        this.handlers[type] = cb;
        return this;
    };

    this.handle = function(data) {
        var h = this;
        function runMessageCallback(message) {
            var data = message.data,
                req_id = message.rid,
                type = message.type;

            if ((req_id !== null) && (req_id !== undefined)) {
                h.current_req_id = req_id;
                h.requestors[ req_id ](data);
                h.current_req_id = undefined;
            } else {
                h.handlers[ type ](data);
            }
        };

        var i;
        if ('forEach' in data) {
            for( i = 0; i < data.length; i++) {
                runMessageCallback(data[i]);
            }
        } else {
            runMessageCallback(data);
        }
    };

    this.consumer = this.handle.bind(this);

    this.ajaxSession = function(params, cb) {
        var req_id = this.req_id++;
        this.requestors[req_id] = cb;

        params.data['rid'] = req_id;
        params.success = this.handle.bind(this);
        return $.ajax(params);
    };

    this.sessionDone = function() {
        if (this.current_req_id !== undefined) {
            delete this.requestors[ this.current_req_id ];
        }
    };
}

