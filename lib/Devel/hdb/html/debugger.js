function Debugger(sel) {
    var dbg = this;
    var $elt = this.$elt = $(sel);
    var perlVarPopoverDelay = 400;  // Time in ms the mouse has to rest over a variable before it gets the value

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
    Handlebars.registerPartial('breakpoint-code-template', $('#breakpoint-code-template').html() );
    Handlebars.registerPartial('action-code-template', $('#action-code-template').html() );
    Handlebars.registerPartial('breakpoint-right-click-template', $('#breakpoint-right-click-template').html() );
    this.templates = {
        fileTab: Handlebars.compile( $('#file-tab-template').html() ),
        navTab: Handlebars.compile( $('#nav-tab-template').html() ),
        navPane: Handlebars.compile( $('#nav-pane-template').html() ),
        currentSubAndArgs: Handlebars.compile( $('#current-sub-and-args-template').html() ),
        breakpointRightClickMenu: Handlebars.compile( $('#breakpoint-right-click-template').html() ),
        saveLoadBreakpointsModal: Handlebars.compile($('#save-load-breakpoints-modal-template').html() ),
        subPickerTemplate: Handlebars.compile($('#sub-picker-template').html() ),
        quickBreakpointModal: Handlebars.compile($('#quick-breakpoint-entry-template').html() ),
    };

    // The step in, over, run buttons
    var $control_buttons = this.$control_buttons = $('.control-button').attr('disabled',true);

    var restInterface = this.restInterface = new RestInterface('');

    function whenStackTabIsShown($elt, cb) {
        var stackId = $elt.closest('.tab-pane').attr('id'),
            relatedTab = $('#stack-tabs a[href="#'+stackId+'"]');
        relatedTab.on('shown.whenStackTabIsShown', function(e) {
            // This cb is fired both when the active tab is switched, and during
            // mouseover of the tab - the latter may be a bug in Bootstrap
            // relatedTarget is true when the anchor was actually clicked, and
            // refers to what was previously the active tab.
            // relatedTarget is undefined during mouseover of the anchor
            if (e.relatedTarget) {
                relatedTab.off('shown.whenStackTabIsShown');
                cb();
            }
        });
    }

    // Called for each .managed-height element when the window resizes
    // Set the height so the the bottom of the element is the bottom of the
    // window.  This makes the scroll bar work for that element
    function setElementHeight() {
        var $elt = $(this),
            offset = $elt.offset(),
            height;

        if ($elt.hasClass('program-code-container') && offset && offset.top === 0) {
            // This one is invisible.  Find which code pane is visible and copy it's height
            height = $('.program-code-container')
                        .filter(function() { return $(this).css('display') === 'block' })
                        .css('height');
        } else {
            // setting the element's height does not account for any padding
            // .css('padding-top') returns a string like "14px", so we need to slice off
            // the last 2 chars
            var padding = parseInt( $elt.css('padding-top').slice(0, -2))
                            +
                          parseInt( $elt.css('padding-bottom').slice(0, -2));
            height = ( $(window).height() - $elt.offset().top - padding ) + 'px';
        }
        $elt.css({'height': height});
    };

    function _tab_mapper(a) { return [ a, parseInt(a.getAttribute('data-frameno')) ]; }
    function _tab_sorter(a,b) { return ( a[1] - b[1] ) }
    function _tab_unmapper(a) { return a[0] }

    this.stackFrameChanged = function(frame_obj, old_frameno, new_frameno) {
        var $tabs = this.stackDiv.find('ul.nav'),
            $tab = $tabs.find('#tab-' + frame_obj.serial),
            $panes = this.stackDiv.find('div.tab-content'),
            $codePane = $panes.find('#pane-' + frame_obj.serial);

        var insertStackFrameForLevel = function($tab_elt, $pane_elt) {
            var tab_elts_in_frame_order = $tabs.children().get().map(_tab_mapper).sort(_tab_sorter).map(_tab_unmapper),
                elt_frameno = $tab_elt.attr('data-frameno'),
                i;

            if (tab_elts_in_frame_order.length == 0
                || elt_frameno > parseInt(tab_elts_in_frame_order[ tab_elts_in_frame_order.length - 1].getAttribute('data-frameno'))
            ) {
                // This new one goes after the last one
                $tabs.append($tab_elt);
            } else {
                for(i = 0; i < tab_elts_in_frame_order.length; i++) {
                    if (elt_frameno <= parseInt(tab_elts_in_frame_order[i].getAttribute('data-frameno'))) {
                        $tab_elt.insertBefore(tab_elts_in_frame_order[i]);
                        break;
                    }
                }
            }
            if ($pane_elt) {
                $panes.append($pane_elt);
            }
        };

        if (new_frameno === null) {
            // a frame got removed
            $tab.remove();
            $codePane.remove();
            $(document).trigger('codePaneRemoved', $codePane);

        } else if (old_frameno === null) {
            // This is a brand new frame
            var is_string_eval = (frame_obj.subname === '(eval)') && (frame_obj.evaltext !== null);
            $tab = $( this.templates.navTab({
                        serial: frame_obj.serial,
                        frameno: new_frameno,
                        longlabel: frame_obj.subroutine,
                        label: frame_obj.subname,
                        filename: frame_obj.filename,
                        lineno: frame_obj.line,
                        is_string_eval: is_string_eval,
                        wantarray: frame_obj.sigil,
                        active: $tabs.children().length == 0
                    }))
                    .tooltip();

            $codePane = $( this.templates.navPane({
                                serial: frame_obj.serial,
                                frameno: new_frameno,
                                filename: frame_obj.filename,
                                active: $panes.children().length == 0
                        }));

            insertStackFrameForLevel($tab, $codePane);

            setElementHeight.call($codePane.find('.managed-height'));

            var needs_args = 1;
            $tab.find('a').on('click', function() {
                if (needs_args) {
                    needs_args = 0;

                    dbg.stackManager.updateFrameWithArgs(frame_obj)
                        .fail(function(jqxhr, text_status, error_thrown) {
                                alert('Error getting details for stack frame '+frameobj.frameno+': '+error_thrown);
                        })
                        .done(function(frame_obj) {
                            var subArgs = frame_obj.args.map(function(arg) {
                                var can_render = (typeof(arg) === 'object') && (arg !== null) && ('render' in arg);
                                return (can_render ? arg.render('condensed') : arg);
                            });
                            $codePane.find('.current-sub-and-args')
                                .append( dbg.templates.currentSubAndArgs({ subroutine: frame_obj.subname, subArgs: subArgs }));
                        });
                }
            });

            this.fileManager.loadFile(frame_obj.filename)
                .done(function($codeTableElt) {
                    var $copy = $codeTableElt.clone();
                    dbg.breakpointManager.markCodePaneLineNumbersForBreakpointsAndActions($copy);
                    $codePane.find('.program-code-container').append($copy);

                    setCurrentLineForCodeTable($copy, frame_obj.line);
                });

        } else {
            // This frame existed before

            if (old_frameno !== new_frameno) {
                // It changed levels
                $tab.detach();
                $tab.attr('data-frameno', new_frameno);
                $codePane.attr('data-frameno', new_frameno);
                insertStackFrameForLevel($tab);
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
        if (line == undefined) {
            return;  // Can happen during cleanup when the program is exiting
        }

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

    function scrollActiveCodeTableLineIntoView(codeTable, line) {
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
    }

    // Set the given line "active" (hightlited) and scroll it into view
    // if necessary
    setCurrentLineForCodeTable = function(codeTable, line) {
        if (line == undefined) {
            return;  // Can happen during cleanup when the program is exiting
        }

        codeTable.find('.active').removeClass('active');
        var activeLine = codeTable.find('.code-line:nth-child('+line+')').addClass('active');

        scrollActiveCodeTableLineIntoView(codeTable, line);
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
    function done_after_stack_update(next_statement) {
        $control_buttons.attr('disabled', false);
        $('#stack-tabs a:first').trigger('click');
        this.watchedExpressionManager.updateExpressions();
        this.setCurrentStatementForCodeTable(next_statement);
    }

    function notifyProgramHasCompletelyExited() {
        $control_buttons.attr('disabled', true);
        restInterface.disconnect();
        $('<span class=alert>Debugged program has exited</span>')
            .appendTo('#controls');
        alert('Debugged program has exited');
    }

    var $original_line_elt;
    var original_line_of_code = '';
    this.setCurrentStatementForCodeTable = function(next_statement) {
        var $topLevelCodePane = $('div.tab-pane[data-frameno=0]'),
            $line = $topLevelCodePane.find('.code-line.active span.code'),
            stackFrame = this.stackManager.frame(0),
            filename = stackFrame.filename,
            lineno = stackFrame.line,
            this_line_code = $line.text();

        if ($original_line_elt) {
            $original_line_elt.html(original_line_of_code);
            $original_line_elt = undefined;
        }

        if (next_statement) {
            // Basic chars that need to be escaped (but not parens)
            var next_statement_re = next_statement.replace(/([.*+?^=!:${}|\[\]\/\\])/g, "\\$1");

            // The deparsed next_statement can have whitespace differences from the original
            next_statement_re = next_statement_re.replace(/\s+/g, '\\s*');

            // parens can also be optional, maybe with whitespace before/after
            next_statement_re = next_statement_re.replace(/\(/g, '\\s*\\(?\\s*');
            next_statement_re = next_statement_re.replace(/\)/g, '\\s*\\)?\\s*');

            // qq(...) is the same as "..."
            next_statement_re = next_statement_re.replace(/(?:"|qq\\s\*\\\()(.*)(?:"|\\\))/, function(quoted, str) {
                                                            return '(?:"|qq\\s*\\(?:\(|\{|\[|\/))' + str + '(?:"|qq\\(?:\)|\}|\]|\/))';
                                                        });

            next_statement_re = RegExp(next_statement_re);
            // Wrap a <span> around the next_statement
            var matched = false;
            var marked_up_this_line_code = this_line_code.replace(next_statement_re, function (code) {
                                                matched = true;
                                                return '<span class="next-statement">' + code + '</span>' });
            if (matched) {
                // save the original look of the current line so we can restore it next time we're
                // back in this function
                $original_line_elt = $line;
                original_line_of_code = $line.html();
                // Write the marked up line back into the window
                $line.html(marked_up_this_line_code);
            } else {
                console.warn("didn't find next_statement on line " + lineno + ": " + next_statement);
            }
        }
    };

    this.controlButtonClicked = function(e) {
        e.preventDefault();

        $control_buttons.attr('disabled', true);

        var button_action = $(e.currentTarget).attr('data-action'),
            rest_method = this.restInterface[button_action],
            response_handler,
            d;

        if (button_action == 'exit') {
            response_handler = function() { $elt.trigger('hangup') };

        } else if (rest_method) {
            response_handler = this.handleControlButtonResponse.bind(this);
        }

        d = rest_method.call(this.restInterface);
        d.done(response_handler);
    };

    this.handleControlButtonResponse = function(response) {
        var events = [],
            watchedExpressionManager = this.watchedExpressionManager;
        if (response.events) {
            events = response.events.map(function(event) {
                return new ProgramEvent(event, watchedExpressionManager);
            });
        }

        this.stackManager.update()
            .progress(this.stackFrameChanged.bind(this))
            .done( done_after_stack_update.bind(this, response.next_statement) );

        events.forEach(function(event) {
            event.render($elt)
                 .done(function(button) {
                    if (button == 'exit') {
                        restInterface.exit()
                                     .done($elt.trigger('hangup'));
                    }
                });
        });
    };

    // Called by popoverPerlVar to draw the resulting data
    var $perlVarPopover = null;
    function drawPerlPopover(data, $prior_elt) {
        if (! $prior_elt.hasClass('hovered-perl-var')) {
            return;  // User moved the pointer before we got the response
        }

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
            $elt.siblings('[data-eval="'+also+'"]').addClass('hovered-perl-var');
        }
        $perlVarPopover = $elt;

        var timer = window.setTimeout(function() {
            if ($perlVarPopover) {
                $perlVarPopover.data('timerid', null);

                restInterface.getVarAtLevel(eval, stack_level)
                             .done(function(data) { drawPerlPopover(data, $elt) });
            }
        }, perlVarPopoverDelay);
        $perlVarPopover.data('timerid', timer);
    }

    function removePopoverPerlVar (e) {
        var $target = $(e.target),
            part_of = $target.attr('data-part-of');

        if (part_of !== undefined) {
            $target = $target.add('[data-eval="'+part_of+'"]');
        }

        $target.removeClass('hovered-perl-var');
        if ($perlVarPopover) {
            $perlVarPopover.popover('destroy');
            $perlVarPopover = undefined;
        }
    }

    function addPerlVarToWatchExpressions(e) {
        var $target = $(e.target),
            expr = $target.attr('data-eval');

        e.preventDefault();
        this.watchedExpressionManager.addExpression(expr, false);
    }

    var $lastControlKeyElement = $control_buttons.filter('[data-action="stepin"]');
    function setKeybindings() {
        // Seems that divs can't receive key events, so we can't bind the
        // handler to this.elt :(
        $(document).keypress(function(e) {
            if ($(e.target).closest('form').length) {
                // Don't handle events for elements like text inputs inside forms
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
                case 66: //B
                    dbg.stackDiv.find('.tab-pane.active .code-line.active span.lineno').click();
                    e.stopPropagation();
                    break;
                case 98: //b
                    dbg.quickBreakpointDialog();
                    e.stopPropagation();
                    break;
            }
        });
    }

    var quick_bp_dialog_open = false;
    function breakpoint_and_continue_to_dialog_handler(params) {
        if (quick_bp_dialog_open) {
            return;
        }
        quick_bp_dialog_open = true;

        var modal = $(this.templates.quickBreakpointModal(params['dialog']));

        modal.appendTo($elt)
            .modal({ backdrop: true, keyboard: true, show: true })
            .on('hidden', function() {
                quick_bp_dialog_open = false;
                modal.remove();
            })
            .keyup(function(e) {
                if (e.keyCode == 27) { // escape - abort editing
                    modal.modal('hide');
                    return false;
                }
            })
            .find('input')
                .focus();

        modal.find('form')
            .submit(function(e) {
                    e.preventDefault();
                    var bp_text = $(e.target).find('[name=breakpoint]').val();

                    parseQuickBreakpointText(bp_text)
                        .done(params['done'])
                        .fail(function(message) {
                            alert(message);
                        })
                        .always(function() {
                            modal.modal('hide');
                        });
            });
    }

    function QB_isCurrentLine(text) {
        var d = $.Deferred();
        if (text.match(/^\.$/)) {  // A single period
            var current_frameno = $('div#stack-panes .tab-pane.active').attr('data-frameno'),
                stack_frame = dbg.stackManager.frame(current_frameno);
            d.resolve(stack_frame.filename, stack_frame.line);
        } else {
            d.reject(undefined);
        }
        return d;
    }

    function QB_isLineNumber(text) {
        var d = $.Deferred();
        var matches = text.match(/^\d+$/);  // match only digits - a line number in the current stackframe's file
        if (matches) {
            var line = dbg.stackDiv.find('.tab-pane.active .code-line[data-lineno='+text+']');
            if (line.length == 0) {
                d.reject('No such line number in the current file');
            } else if (line.hasClass('unbreakable')) {
                d.reject('Line ' + text + ' is not breakable');
            } else {
                var file = dbg.stackDiv.find('.tab-pane.active .program-code-container').attr('data-filename');
                d.resolve(file, text);
            }
        } else {
            d.reject(undefined);
        }
        return d.promise();
    }

    function QB_isFQSubroutine(text) {
        var d = $.Deferred();
        var matches = text.match(/^(.+?::\w+)(?::(\d+))?$/); // match "package::subname" or "package::subname:line"
        if (matches) {
            var subname = matches[1],
                line = matches[2];

            restInterface.subInfo(subname)
                    .done(function(data) {
                        _QB_findBreakableLineInSub(line, d, data);
                    })
                    .fail(function() {
                        d.reject(undefined);
                    })

        } else {
            d.reject(undefined);
        }
        return d.promise();
    }

    function QB_isSubroutine(text) {
        var d = $.Deferred();
        var matches = text.match(/^(.+?)(?::(\d+))?$/);  // match either "string" or "string:numbers"
        if (matches) {
            var subname = matches[1],
                line = matches[2],
                current_frameno = $('div#stack-panes .tab-pane.active').attr('data-frameno'),
                stack_frame = dbg.stackManager.frame(current_frameno),
                current_package = stack_frame.package;

            restInterface.subInfo(current_package + '::' + subname)
                        .done(function(data) {
                            _QB_findBreakableLineInSub(line, d, data);
                        })
                        .fail(function(data) {
                            d.reject(undefined);
                        });
        } else {
            d.reject(undefined);
        }
        return d.promise();
    }

    function _QB_findBreakableLineInSub(requested_line_str, deferred, subinfo_data) {
        var start_breakable_search,
            sub_start_line = parseInt(subinfo_data.line, 10),
            sub_end_line = parseInt(subinfo_data.end, 10),
            requested_line = parseInt(requested_line_str, 10);

        if (requested_line_str) {  // They wanted to stop on a particular line
            var sub_length = sub_end_line - sub_start_line;
            if (requested_line > sub_length) {
                deferred.reject(requested_line_str + ' is outside the range of sub ' + subinfo_data.subroutine);
            }
            start_breakable_search = sub_start_line + requested_line;

            if (dbg.fileManager.isBreakable(subinfo_data.filename, sub_start_line)) {
                // if the sub's first line is breakable, then line "1" of the sub
                // is the same as the sub's start line
                start_breakable_search = start_breakable_search - 1;
            }

        } else {
            start_breakable_search = sub_start_line;
        }

        for(var break_on_line = start_breakable_search; break_on_line < subinfo_data.end; break_on_line++) {
            if (dbg.fileManager.isBreakable(subinfo_data.filename, break_on_line)) {
                deferred.resolve(subinfo_data.filename, break_on_line);
            }
        }
        deferred.reject("Couldn't file a breakable line within '"
                        + subinfo_data.subroutine
                        + '. Tried line ' + requested_line + ' to the end of the function');
    }

    function QB_isFile(text) {
        var d = $.Deferred();
        var matches = text.match(/^(.+?):(\d+)$/);  // match "string:numbers"
        if (matches) {
            var filename = matches[1],
                line = matches[2];
            if (dbg.fileManager.isLoaded(filename)) {
                if (dbg.fileManager.isBreakable(filename, line)) {
                    d.resolve(filename, line);
                } else {
                    d.reject(filename + ':' + line + ' is not breakable');
                }
            } else {
                d.reject(undefined);
            }
        } else {
            d.reject(undefined);
        }
        return d.promise();
    }

    function QB_unparsable(text) {
        var d = $.Deferred();
        d.reject("Could not parse breakpoint '" + text + "'");
        return d.promise();
    }

    var quick_breakpoint_resolvers = [
        QB_isCurrentLine,
        QB_isLineNumber,
        QB_isFQSubroutine,
        QB_isSubroutine,
        QB_isFile,
        QB_unparsable,
    ];
    function parseQuickBreakpointText(text) {
        var d = $.Deferred();

        function tryBreakpointResolver(i) {
            var resolver = quick_breakpoint_resolvers[i],
                p = resolver(text);

            p.done(function(filename, line) {
                d.resolve(filename, line);  // try just putting d in the done()?
            })
            .fail(function(message) {
                if (message) {
                    d.reject(message);
                } else {
                    tryBreakpointResolver(i + 1);
                }
            })
        }

        tryBreakpointResolver(0);
        return d.promise();
    }

    this.quickBreakpointDialog = function() {
        breakpoint_and_continue_to_dialog_handler.call(this, {
            dialog: {
                title: 'Quick-add Breakpoint',
                prompt: 'New breakpoint',
                ok_button: 'Add'
            },
            done: function(filename, line) {
                dbg.breakpointManager.createBreakpoint({filename: filename, line: line});
            }
        });
    };

    this.continueToDialog = function() {
        breakpoint_and_continue_to_dialog_handler.call(this, {
            dialog: {
                title: 'Continue To...',
                prompt: 'Continue to',
                ok_button: 'Continue'
            },
            done: function(filename, line) {
                restInterface.createBreakpoint({
                    filename: filename,
                    line: line,
                    once: 1,
                    code: '1'
                });
                $control_buttons.filter('[data-action="continue"]')
                                        .click();
            }
        });
    };
                                    
    var $breakpointPane = $('#breakpoint-container'),
        $breakpointToggleIcon = $('#breakpoint-container-handle-icon');

    function breakpointPaneIsExtended(value) {
        if (value === undefined) {
            return $breakpointPane.hasClass('extended');
        } else if (value) {
            $breakpointPane.addClass('extended');
        } else {
            $breakpointPane.removeClass('extended');
        }
    }

    function toggleBreakpointContainer(e) {
        if (breakpointPaneIsExtended()) {
            $breakpointPane.animate(
                { width: 0 },
                'fast',
                function() {
                    breakpointPaneIsExtended(false);
                    $breakpointToggleIcon.removeClass('icon-chevron-left').addClass('icon-chevron-right');
                });
        } else {
            breakpointPaneIsExtended(true);
            $breakpointPane.animate(
                { width: $('#side-tray').width() },
                'fast',
                function() {
                    $breakpointToggleIcon.removeClass('icon-chevron-right').addClass('icon-chevron-left');
                });
        }
    }

    // Set up handlers for moving the border between the code pane and the watch window
    function setupResizeWatchPane() {
        var $divider = $('#drag-divider'),
            $controls = $('#controls'),
            handleWidth = $('#breakpoint-container-handle').outerWidth(),
            $ghostDivider;

        $(document).on('mousedown.resize', '#drag-divider', function(e) {
            e.preventDefault();
            var dividerOffset = $divider.offset();

            $ghostDivider = $('<div id="ghost-divider">')
                            .css({
                                height: $divider.outerHeight(),
                                top: dividerOffset.top,
                                left: dividerOffset.left
                            })
                            .appendTo('body');

            var minLeft = $controls.offset().left + $controls.width();
            $(document).on('mousemove.resize', function(e) {
                if (e.pageX <= minLeft) {
                    // Don't let it get smaller than the control buttons width
                    return;
                }
                $ghostDivider.css('left', e.pageX+2);
            });
        });

        $(document).on('mouseup.resize', function(e) {
            if ($ghostDivider) {
                var width = $(window).width() - $ghostDivider.offset().left;

                $('#columnator').css('padding-right', '' +  width + 'px');

                $divider.next()
                            .css({  width: width - 1 - handleWidth,
                                    'margin-right': 1 - width + handleWidth });

                if (breakpointPaneIsExtended()) {
                    $breakpointPane.css('width', $('#side-tray').width());
                }

                $ghostDivider.remove();
                $(document).off('mousemove.resize');
                $ghostDivider = undefined;
            }
        });
    }

    // Called when the "+" button in the file tab is clicked
    function pickFileToLoad(e) {
        var fileManager = this.fileManager,
            that = this,
            modal;

        function generateNewTabId() {
            var id = 'stack';  // A tab that will always exist to force a pick
            while( $('#file-content #'+id).length) {
                id = Math.floor(Math.random()*1000000);
            }
            return id;
        }

        function renderNewFile($codeElt, filename, line) {
            var tabId = generateNewTabId(),
                $newTab = $( that.templates.fileTab({ id: tabId, label: filename, closable: true})),
                $container = $( that.templates.navPane({ serial: tabId, filename: filename, banner: filename })),
                $copy = $codeElt.clone().attr('id', tabId);

            // add the new nav tab
            $('#add-file').closest('li').before($newTab)

            // add the new nav pane contents
            dbg.breakpointManager.markCodePaneLineNumbersForBreakpointsAndActions($copy);
            $container.find('.program-code-container').append($copy);
            $('#file-content').append($container);

            // Make the new tab active
            $newTab.find('a').click();

            // Set its height
            setElementHeight.call($container.find('.managed-height'));
            // Scroll the requested sub into view
            _scrollCodeTableLineIntoView($copy, line);
        }

        function getSubInfo(pkg, subname) {
            var fq_name = pkg + '::' + subname;
            modal.modal('hide');
            restInterface.subInfo(fq_name)
                .done(function(subinfo) {
                    fileManager.loadFile(subinfo.filename)
                                .done(function($codeElt) {
                                    renderNewFile($codeElt, subinfo.filename, subinfo.line);
                                })
                                .fail(function(jqxhr, text_status, error_thrown) {
                                    alert('Loading file '+subinfo.filename+' failed: '+error_thrown)
                                });
                })
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert('Getting subroutine info for '+fq_name+' failed: '+error_thrown);
                });
        }

        modal = $( this.templates.subPickerTemplate())
                .appendTo($elt)
                .modal({ backdrop: true, keyboard: true, show: true })
                .on('hidden', function() { modal.remove() })
                .filePicker({ picked: getSubInfo, restInterface: restInterface });
    }

    function removeLoadedFile(e) {
        var $tabLi = $(e.currentTarget).closest('li'),
            tabId = $tabLi.find('a').attr('href'),
            $filePane = $(tabId),
            prevTabLink = $tabLi.prev().find('a');

        prevTabLink.click();
        $tabLi.remove();
        $filePane.remove();
    }

    function _loadConfig_response_handler_for_saveLoadBreakpoints(settings) {
        dbg.breakpointManager.sync();

        if (settings['additional'] && settings['additional']['watch_expressions']) {
            var watch_expressions = settings['additional']['watch_expressions'];
            for (var i = 0; i < watch_expressions.length; i++) {
                dbg.watchedExpressionManager.addExpression( watch_expressions[i], false);
            }
        }
    }

    this.defaultConfigFileName = function() {
        return this.programName + '.hdb';
    };

    function saveLoadBreakpoints(e) {
        e.preventDefault();
        var isSave = $(e.currentTarget).attr('id') === 'save-breakpoints',
            savefile = dbg.defaultConfigFileName(),
            modal = $(this.templates.saveLoadBreakpointsModal({
                                            action: isSave ? 'Save' : 'Load',
                                            filename: savefile
                                        }));
        modal.appendTo($elt)
             .modal({ backdrop: true, keyboard: true, show: true })
             .focus()
             .on('hidden', function() { modal.remove() });

        modal.find('form')
             .submit(function(e) {
                    e.preventDefault();
                    var ri_method = restInterface[isSave ? 'saveConfig' : 'loadConfig'];
                        additional = {};

                    if (isSave) {
                        additional['watch_expressions'] = dbg.watchedExpressionManager.expressions();
                        console.log(additional);
                    }

                    ri_method.call(restInterface, savefile, additional)
                             .fail(function(jqxhr, text_status, error_thrown) {
                                alert((isSave ? 'Saving' : 'Loading')
                                        + ' config failed: ' + error_thrown);
                                })
                            .done(function(settings) {
                                 if (! isSave) {
                                    _loadConfig_response_handler_for_saveLoadBreakpoints(settings)
                                }
                            })
                            .always(function() {
                                modal.modal('hide').remove();
                            });
                });
    }

    // Initialization
    this.restInterface.programName()
        .done(function(program_name) {
            $elt.find('li#program-name a').html(program_name)
                                          .attr('title', program_name);
            dbg.programName = program_name;
        });
    this.fileManager = new FileManager(this.restInterface);

    this.breakpointManager = new BreakpointManager(this.$elt, this.restInterface);
    this.watchedExpressionManager = new WatchedExprManager(this.restInterface);
    this.watchedExpressionManager.loadWatchpoints();

    this.stackManager = new StackManager(this.restInterface);
    this.stackManager.initialize()
        .progress(this.stackFrameChanged.bind(this))
        .done(function(status) {
                done_after_stack_update.call(dbg);
                dbg.setCurrentStatementForCodeTable(status.next_statement);
                dbg.breakpointManager.sync();
        });

    // Events
    $elt.on('click', '.control-button[name="stepin"][disabled!="disabled"]',    this.controlButtonClicked.bind(this))
        .on('click', '.control-button[name="stepout"][disabled!="disabled"]',   this.controlButtonClicked.bind(this))
        .on('click', '.control-button[name="stepover"][disabled!="disabled"]',  this.controlButtonClicked.bind(this))
        .on('click', '.control-button[name="continue"][disabled!="disabled"]',  this.controlButtonClicked.bind(this))
        .on('click', '.control-button[name="exit"][disabled!="disabled"]',      this.controlButtonClicked.bind(this))
        .on('click', '.control-button[name="continue-to"][disabled!="disabled"]', this.continueToDialog.bind(this))
        .on('mouseenter', '.popup-perl-var', popoverPerlVar.bind(this))
        .on('mouseleave', '.popup-perl-var', removePopoverPerlVar.bind(this))
        .on('contextmenu', '.popup-perl-var', addPerlVarToWatchExpressions.bind(this))
        .on('click', '.current-sub-and-args', setCurrentLineForCodeTableEvent.bind(this))
        .on('hangup', notifyProgramHasCompletelyExited.bind(this))
        .on('click', '#add-file', pickFileToLoad.bind(this))
        .on('click', '.remove-loaded-file', removeLoadedFile.bind(this))
        .on('click', '.save-load-breakpoints', saveLoadBreakpoints.bind(this));

    $('#breakpoint-container-handle').click(toggleBreakpointContainer.bind(this));

    setKeybindings();
    setupResizeWatchPane();

    $('.managed-height').each(setElementHeight);
    $(window).resize(function() { $('.managed-height').each(setElementHeight) });

}
