function BreakpointManager($main_elt, rest_interface) {
    var breakpoints = {}, // keyed by filename, then by line number
        actions     = {},
        $breakpointsList = $main_elt.find('#breakpoints-list'),
        breakpointPaneItemTemplate = Handlebars.compile( $('#breakpoint-pane-item-template').html() ),
        breakpointConditionTemplate = Handlebars.compile( $('#breakpoint-condition-template').html() ),
        breakpointRightClickTemplate = Handlebars.compile( $('#breakpoint-right-click-template').html() );

    this.forEachBreakpoint = function(cb) {
        
    };

    function getBreakpointOrAction(storage, filename, line) {
        if (storage[filename]) {
            return storage[filename][line];
        } else {
            return undefined;
        }
    };

    this.getBreakpoint = function(filename, line) {
        return getBreakpointOrAction(breakpoints, filename, line);
    };

    this.getAction = function(filename, line) {
        return getBreakpointOrAction(actions, filename, line);
    };

    function resolveForFilenameAndLine(storage, filename, line) {
        var bp;
        if (! filename in storage) {
            storage[filename] = {};
        }

        bp = storage[filename][line];
        if (!bp) {
            bp = new Breakpoint({filename: filename, line: line});
            storage[filename][line] = bp;
        }
        return bp;
    }

    function notifyBreakpointChange(signal, filename, arg) {
        $('.breakpoint-listener[data-filename="'+filename+'"]')
            .trigger(signal, arg);
    }

    this.changeBreakpoint = function(filename, line, code, inactive) {
        var bp = resolveForFilenameAndLine(breakpoints, filename, line);
        bp.code = code;
        bp.inactive = inactive;

        notifyBreakpointChange('breakpointChanged', filename, bp);
    };

    this.changeAction = function(filename, line, code, inactive) {
        var bp = resolveForFilenameAndLine(actions, filename, line);
        bp.code = code;
        bp.inactive = inactive;
    };

    this.removeAction = function(filename, line) {
        var action = actions[filename][line];
        delete actions[filename][line];
    };

    function filenameForCodePane($codePane) {
        $codePane.find('[data-filename]').attr('data-filename');
    }

    function matchingLineElementsForBreakpoint(bp) {
        return $('.breakpoint-listener[data-filename="'+bp.filename+'"] .code-line[data-lineno="'+bp.line+'"]');
    }

    function updateBreakpointPaneForDeletedBreakpoint(bp, type) {
        var $elt = $breakpointsList.find('[data-filename="'+bp.filename+'"][data-lineno="'+bp.line+'"]'),
            otherType = type == 'breakpoint' ? 'action' : 'breakpoint',
            otherTypeClass = otherType + '-details';
            otherTypeIsNone = $elt.find('.'+otherTypeClass+' .none').length > 0;

        if (otherTypeIsNone) {
            // Both the breakpoint and action are removed - remove the element
            $elt.remove();
        } else {
            // just blank out the breakpoint or action
            var $subElt = $elt.find('.'+type+'-details .condition').html(breakpointConditionTemplate({}));
        }
    }

    var updateForDeletedBreakpoint, updateForDeletedAction;
    (function() {
        var deleter = function(type) {
            var all_classes = type + ' conditional-' + type + ' inactive-'+type;
            return function(bp) {
                // clear code pane line elements
                matchingLineElementsForBreakpoint(bp)
                    .removeClass(all_classes);

                // remove item from the breakpoint pane
                updateBreakpointPaneForDeletedBreakpoint(bp, type);
            };
        };

        updateForDeletedBreakpoint = deleter('breakpoint');
        updateForDeletedAction = deleter('action');
    })();

    function updateBreakpointPaneElementForChangedBreakpoint(bp, type) {
        var filename = bp.filename,
            line = bp.line,
            eltClass = type + '-details',
            $elts = $('.breakpoint-marker[data-filename="'+filename+'"][data-lineno="'+line+'"] .'+eltClass);

        if ($elts.length) {
            // Updating an existing breakpoint list item
            $elts.find('input[type="checkbox"]').prop('checked', bp.inactive ? false : true);
            $elts.find('.condition').html(breakpointConditionTemplate({condition: bp.code}));

        } else {
            // Add a new list item to the bottom of the list
            var params = type == 'breakpoint'
                            ? {condition: bp.code, conditionEnabled: ! bp.inactive}
                            : {action: bp.code, actionEnabled: ! bp.inactive};
            params.filename = bp.filename;
            params.lineno = bp.line;
            $breakpointsList.append( breakpointPaneItemTemplate(params));
        }
    }

    var updateForChangedBreakpoint, updateForChangedAction;
    (function() {
        var maker = function(type) {
            var all_classes = type + ' conditional-' + type + ' inactive-'+type;
            return function(bp) {
                var new_classes = type;
                if (bp.code != '1') {
                    new_classes += ' conditional-'+type;
                }
                if (bp.inactive) {
                    new_classes += ' inactive-'+type;
                }
                // Update code pane lines
                matchingLineElementsForBreakpoint(bp)
                    .removeClass(all_classes)
                    .addClass(new_classes);

                // Update breakpoint pane
                updateBreakpointPaneElementForChangedBreakpoint(bp, type);
            };
        };
        updateForChangedBreakpoint = maker('breakpoint');
        updateForChangedAction = maker('action')
    })();

    this.removeBreakpoint = function(filename, line) {
        var bp = breakpoints[filename][line];
        delete breakpoints[filename][line];
        rest_interface.deleteBreakpoint(bp.href)
            .done(function() {
                updateForDeletedBreakpoint(bp)
            });
    };

    function storeCreatedBreakpoint(bp) {
        var filename = bp.filename;

        if (! breakpoints[filename]) {
            breakpoints[filename] = {};
        }
        breakpoints[filename][bp.line] = bp;
    }

    function storeCreatedAction(bp) {
        var filename = bp.filename;

        if (! actions[filename]) {
            actions[filename] = {};
        }
        actions[filename][bp.line] = bp;
    }

    this.createBreakpoint = function(params) {
        rest_interface.createBreakpoint(params)
            .done(function(data) {
                var bp = new Breakpoint(data);

                storeCreatedBreakpoint(bp);
                updateForChangedBreakpoint(bp);
            })
            .fail(function(jqxhr, text_status, error_thrown) {
                alert('Setting breakpoint failed: '+error_thrown);
            });
    };

    this.createAction = function(params) {
        rest_interface.createAction(params)
            .done(function(data) {
                var bp = new Breakpoint(data);

                storeCreatedAction(bp);
                updateForChangedAction(bp);
            })
            .fail(function(jqxhr, text_status, error_thrown) {
                alert('Setting action failed: '+error_thrown);
            });
    };

    function breakableLineClicked(e) {
        var $elt = $(e.target),
            filename = $elt.closest('.program-code').attr('data-filename'),
            line = $elt.closest('.code-line').attr('data-lineno');

        if (this.getBreakpoint(filename, line)) {
            this.removeBreakpoint(filename, line);
        } else {
            this.createBreakpoint({filename: filename, line: line, code: '1'})
        }
    }

    function breakableLineRightClicked(e) {

    }

    // synchronize our list of breakpoints/actions with the debugged program
    this.sync = function() {
        var original_breakpoints = breakpoints;
            breakpoints = {},
            that = this;

        function previously_existed(filename, line) {
            return original_breakpoints[filename] && original_breakpoints[filename][line];
        }

        function copy_to_breakpoints(filename, line) {
            var bp = original_breakpoints[filename][line];
            delete original_breakpoints[filename][line];
            if (! breakpoints[filename]) {
                breakpoints[filename] = {};
            }
            breakpoints[filename][line] = bp;
            return bp;
        }

        rest_interface.getBreakpoints()
            .fail(function(jqxhr, text_status, error_thrown) {
                alert('Getting breakpoints failed: ' + error_thrown);
            })
            .done(function(breakpoint_list) {
                breakpoint_list.forEach(function(bp_params) {
                    if (previously_existed(bp_params.filename, bp_params.line)) {
                        var bp = copy_to_breakpoints(bp_params.filename, bp_params.line),
                            changed = (bp.code != bp_params.code) || (bp.inactive != bp_params.inactive);
                        if (changed) {
                            updateForChangedBreakpoint(bp);
                        }

                    } else {
                        var bp = new Breakpoint(bp_params);
                        storeCreatedBreakpoint(bp);
                    }
                });
            });
    };

    // Remove the breakpoint popover if the user clicks outside of it
    var breakpointPopover;
    function clearBreakpointEditorPopover(e) {
        if (breakpointPopover && ($(e.target).closest('.popover').length == 0)) {
            e.preventDefault();
            e.stopPropagation();
            breakpointPopover.popover('destroy');
            breakpointPopover = undefined;
        }
    }

    function breakableLineRightClicked(e) {
        e.preventDefault();

        var $target_lineno = $(e.target),
            filename = $target_lineno.closest('[data-filename]').attr('data-filename'),
            line = $target_lineno.closest('[data-lineno]').attr('data-lineno'),
            breakpoint = this.getBreakpoint(filename, line),
            action = this.getAction(filename, line),
            menu;

        menu = breakpointRightClickTemplate({ filename: filename, lineno: line,
                                              conditionEnabled: (breakpoint && ! breakpoint.inactive),
                                              condition: (breakpoint && breakpoint.code),
                                              actionEnabled: (action && ! action.inactive),
                                              action: ( action && action.code)
                                            });

        if (breakpointPopover) {
            breakpointPopover.popover('destroy');
        }
        breakpointPopover = $target_lineno.popover({ html: true,
                                                trigger: 'manual',
                                                placement: 'right',
                                                title: filename + ' ' + line,
                                                container: $main_elt,
                                                content: menu })
                                        .popover('show');
    }

    function inactiveBreakpointCheckboxClicked(e) {
        var $checkbox = $(e.target),
            state = $checkbox.is(':checked'),
            $listItem = $checkbox.closest('.breakpoint-marker'),
            filename = $listItem.attr('data-filename'),
            line = $listItem.attr('data-lineno'),
            isBreakpoint = $checkbox.closest('.details').hasClass('breakpoint-details'),
            bp = isBreakpoint ? this.getBreakpoint(filename, line) : this.getAction(filename, line);

        if (bp === undefined) {
            // When we get here, the checkbox is already checked?!
            // we don't get a chance to preventDefault
            $checkbox.attr('checked', false);
            return;
        }

        rest_interface.changeBreakpoint(bp.href, { inactive: state ? 0 : 1 })
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert('Changing breakpoint failed: ' + error_thrown);
                })
                .done(function() {
                    bp.inactive = $checkbox.is(':checked') ? 0 : 1;
                    updateForChangedBreakpoint(bp);
                });
    }

    function submitChangedBreakpointCondition(e) {
        e.preventDefault();
        var $form = $(e.target),
            $input = $form.find('input'),
            $container = $form.closest('.condition'),
            bp = e.data.bp,
            isBreakpoint = e.data.isBreakpoint,
            isNewBp = bp === undefined ? true : false,
            newCondition = $input.val();

        if (isNewBp) {
            var addMethod = isBreakpoint
                                ? this.createBreakpoint.bind(this)
                                : this.createAction.bind(this);
            addMethod({filename: e.data.filename, line: e.data.line, code: newCondition});
        } else {
            var changeMethod = isBreakpoint
                                ? rest_interface.changeBreakpoint.bind(rest_interface)
                                : rest_interface.changeAction.bind(rest_interface);

            changeMethod(bp.href, { code: newCondition })
                .fail(function(jqxhr, text_status, error_thrown) {
                    $container.empty().append( breakpointConditionTemplate({ condition: bp.code }));
                    alert('Changing breakpoint failed: ' + error_thrown);
                })
                .done(function() {
                    bp.code = newCondition;
                    var updater = isBreakpoint
                                    ? updateForChangedBreakpoint
                                    : updateForChangedAction;
                    updater(bp);
                });
        }
    }

    function editBreakpointCondition(e) {
        var $elt = $(e.target),
            isBreakpoint = $elt.closest('.details').hasClass('breakpoint-details'),
            $listItem = $elt.closest('.breakpoint-marker'),
            filename = $listItem.attr('data-filename'),
            line = $listItem.attr('data-lineno'),
            bp = isBreakpoint ? this.getBreakpoint(filename, line) : this.getAction(filename, line),
            bpCode = bp ? bp.code : '',
            $form = $('<form><input type="text" value="' + bpCode + '"></form>'),
            submitData = { bp: bp, isBreakpoint: isBreakpoint, filename: filename, line: line };

        $form.on('submit', submitData, submitChangedBreakpointCondition.bind(this))
             .find('input')
                .keyup(function(e) {
                    if (e.keyCode == 27) { // escape - abort editing
                        e.preventDefault();
                        $elt.empty().append( breakpointConditionTemplate({ condition: bp.code }));
                    }
                });

        $elt.empty().append($form);
        $form.find('input').focus().select();
    }

    $main_elt.on('click', '.code-line:not(.unbreakable) .lineno', breakableLineClicked.bind(this))
             .on('contextmenu', '.code-line:not(.unbreakable) .lineno', breakableLineRightClicked.bind(this))
             .on('click', clearBreakpointEditorPopover.bind(this))
             .on('click', 'input[type="checkbox"].bpaction-toggle', inactiveBreakpointCheckboxClicked.bind(this))
             .on('dblclick', '.bpaction-condition', editBreakpointCondition.bind(this));
}

function Breakpoint(params) {
    var bp = this;
    ['filename','line','code','inactive','href'].forEach(function(key) {
        bp[key] = params[key];
    });
    return this;
}
