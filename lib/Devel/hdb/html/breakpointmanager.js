function BreakpointManager($main_elt, rest_interface) {
    var breakpoints = {}, // keyed by filename, then by line number
        actions     = {},
        $breakpointsList = $main_elt.find('#breakpoints-list'),
        breakpointPaneItemTemplate = Handlebars.compile( $('#breakpoint-pane-item-template').html() ),
        breakpointConditionTemplate = Handlebars.compile( $('#breakpoint-condition-template').html() );

    this.forEachBreakpoint = function(cb) {
        
    };

    this._getThing = function(storage, filename, line) {
        if (storage[filename]) {
            return storage[filename][line];
        } else {
            return undefined;
        }
    };

    this.getBreakpoint = function(filename, line) {
        return this._getThing(breakpoints, filename, line);
    };

    this.getAction = function(filename, line) {
        return this._getThing(actions, filenane, line);
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
        updateForDeletedAction = deleter('bpaction');
    })();

    function updateBreakpointPaneElementForChangedBreakpoint(bp, type) {
        var filename = bp.filename,
            line = bp.line,
            eltClass = type + '-details',
            $elt = $breakpointsList.find('[data-filename="'+filename+'"][data-lineno="'+line+'"] .'+eltClass);

        $elt.find('input[type="checkbox"]').prop('checked', bp.inactive ? false : true);
        $elt.find('.condition').html(breakpointConditionTemplate({condition: bp.code}));
    }

    function updateBreakpointPaneElementForNewBreakpoint(bp, type) {
        var params = type == 'breakpoint'
                        ? {condition: bp.code, conditionEnabled: ! bp.inactive}
                        : {action: bp.code, actionEnabled: ! bp.inactive};
        params.filename = bp.filename;
        params.lineno = bp.line;
        $breakpointsList.append( breakpointPaneItemTemplate(params));
    }

    var updateForChangedBreakpoint, updateForChangedAction;
    (function() {
        var maker = function(type) {
            var all_classes = type + ' conditional-' + type + ' inactive-'+type;
            return function(bp, is_new) {
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
                if (is_new) {
                    updateBreakpointPaneElementForNewBreakpoint(bp, type);
                } else {
                    updateBreakpointPaneElementForChangedBreakpoint(bp, type);
                }
            };
        };
        updateForChangedBreakpoint = maker('breakpoint');
        updateForChangedAction = maker('bpaction')
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

    this.createBreakpoint = function(params) {
        rest_interface.createBreakpoint(params)
            .done(function(data) {
                var bp = new Breakpoint(data);

                storeCreatedBreakpoint(bp);
                updateForChangedBreakpoint(bp, true);
            })
            .fail(function(jqxhr, text_status, error_thrown) {
                alert('Setting breakpoint failed: '+error_thrown);
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
                            updateForChangedBreakpoint(bp, false);
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
            e.stopPropogation();
            breakpointPopover.popover('destroy');
            breakpointPopover = undefined;
        }
    }

    function inactiveBreakpointCheckboxClicked(e) {
        var $checkbox = $(e.target),
            state = $checkbox.is(':checked'),
            $listItem = $checkbox.closest('.breakpoint-marker'),
            filename = $listItem.attr('data-filename'),
            line = $listItem.attr('data-lineno'),
            isBreakpoint = $checkbox.closest('.details').hasClass('breakpoint-details'),
            bp = isBreakpoint ? this.getBreakpoint(filename, line) : this.getAction(filename, line);

        rest_interface.changeBreakpoint(bp.href, { inactive: state ? 0 : 1 })
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert('Changing breakpoint failed: ' + error_thrown);
                })
                .done(function() {
                    bp.inactive = $checkbox.is(':checked') ? 0 : 1;
                    updateForChangedBreakpoint(bp, false);
                });
    }

    function submitChangedBreakpointCondition(e) {
        e.preventDefault();
        var $form = $(e.target),
            $input = $form.find('input'),
            $container = $form.closest('.condition'),
            bp = e.data.bp,
            newCondition = $input.val(),
            changeMethod = e.data.isBreakpoint
                                ? rest_interface.changeBreakpoint.bind(rest_interface)
                                : rest_interface.changeAction.bind(rest_interface);

        changeMethod(bp.href, { code: newCondition })
            .fail(function(jqxhr, text_status, error_thrown) {
                $container.empty().append( breakpointConditionTemplate({ condition: bp.code }));
                alert('Changing breakpoint failed: ' + error_thrown);
            })
            .done(function() {
                bp.code = newCondition;
                updateForChangedBreakpoint(bp, false);
            });
    }

    function editBreakpointCondition(e) {
        var $elt = $(e.target),
            isBreakpoint = $elt.closest('.details').hasClass('breakpoint-details'),
            $listItem = $elt.closest('.breakpoint-marker'),
            filename = $listItem.attr('data-filename'),
            line = $listItem.attr('data-lineno'),
            bp = isBreakpoint ? this.getBreakpoint(filename, line) : this.getAction(filename, line),
            $form = $('<form><input type="text" value="' + bp.code + '"></form>');

        $form.on('submit', { bp: bp, isBreakpoint: isBreakpoint }, submitChangedBreakpointCondition.bind(this))
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
             .on('click', clearBreakpointEditorPopover.bind(this));

    $breakpointsList.on('click', 'input[type="checkbox"]', inactiveBreakpointCheckboxClicked.bind(this))
                    .on('dblclick', '.condition', editBreakpointCondition.bind(this));
}

function Breakpoint(params) {
    var bp = this;
    ['filename','line','code','inactive','href'].forEach(function(key) {
        bp[key] = params[key];
    });
    return this;
}
