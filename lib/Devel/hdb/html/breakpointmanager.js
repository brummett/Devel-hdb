function BreakpointManager($main_elt, rest_interface) {
    var breakpoints = {}, // keyed by filename, then by line number
        actions     = {},
        $breakpointsList = $main_elt.find('#breakpoints-list'),
        breakpointPaneItemTemplate = Handlebars.compile( $('#breakpoint-pane-item-template').html() ),
        breakpointConditionTemplate = Handlebars.compile( $('#breakpoint-code-template').html() ),
        breakpointRightClickTemplate = Handlebars.compile( $('#breakpoint-right-click-template').html() );

    function getBPAction(type, filename, line) {
        var storage = type === 'breakpoint' ? breakpoints : actions;
        if (storage[filename]) {
            return storage[filename][line];
        } else {
            return undefined;
        }
    };

    this.getBreakpoint = function(filename, line) {
        return getBPAction('breakpoint', filename, line);
    };

    this.getAction = function(filename, line) {
        return getBPAction('action', filename, line);
    };

    function resolveForFilenameAndLine(type, filename, line) {
        var storage = type === 'breakpoint' ? breakpoints : actions,
            bp;
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

    function removeBPAction (type, filename, line) {
        var storage = type === 'breakpoint' ? breakpoints : actions,
            deleteMethod = rest_interface[ type == 'breakpoint' ? 'deleteBreakpoint' : 'deleteAction'],
            bp;

        if ((! storage[filename]) || (! (bp = storage[filename][line]))) {
            return;
        }

        delete storage[filename][line];
        deleteMethod.call(rest_interface, bp.href)
            .done(function() {
                updateForDeletedBPAction(type,  bp);
            })
            .fail(function(jqxhr, text_status, error_thrown) {
                alert('Removing '+type+' failed: '+error_thrown);
            });
    };

    function filenameForCodePane($codePane) {
        $codePane.find('[data-filename]').attr('data-filename');
    }

    function matchingLineElementsForBreakpoint(bp, $codePane) {
        if ($codePane) {
            return $codePane.find('.code-line[data-lineno="'+bp.line+'"]');
        } else {
            return $('.breakpoint-listener[data-filename="'+bp.filename+'"] .code-line[data-lineno="'+bp.line+'"]');
        }
    }

    function updateBreakpointPaneForDeletedBPAction(type, bp) {
        var $elt = $breakpointsList.find('[data-filename="'+bp.filename+'"][data-lineno="'+bp.line+'"]'),
            otherType = type == 'breakpoint' ? 'action' : 'breakpoint',
            otherTypeClass = otherType + '-details';
            otherTypeIsNone = $elt.find('.'+otherTypeClass+' .none').length > 0;

        if (otherTypeIsNone) {
            // Both the breakpoint and action are removed - remove the element
            $elt.remove();
        } else {
            // just blank out the breakpoint or action
            var $subElt = $elt.find('.'+type+'-details .bpaction-code').html(breakpointConditionTemplate({}));
        }
    }

    function updateForDeletedBPAction(type, bp) {
        var all_classes = type + ' conditional-' + type + ' inactive-'+type;

        // clear code pane line elements
        matchingLineElementsForBreakpoint(bp)
            .removeClass(all_classes);

        // remove item from the breakpoint pane
        updateBreakpointPaneForDeletedBPAction(type, bp);
    };

    function updateBreakpointPaneElementForChangedBPAction(type, bp) {
        var filename = bp.filename,
            line = bp.line,
            eltClass = type + '-details',
            matchFileAndLine = '.breakpoint-marker[data-filename="'+filename+'"][data-lineno="'+line+'"]',
            $existingElts = $(matchFileAndLine + ' .'+eltClass),
            $eltsInBreakpointList = $breakpointsList.find(matchFileAndLine);

        // Update already-existing on-screen items
        // Either in the breakpoints list or the right-click menu
        $existingElts.find('input[type="checkbox"]').prop('checked', bp.inactive ? false : true);
        $existingElts.find('.bpaction-code').html(breakpointConditionTemplate({condition: bp.code}));

        if ($eltsInBreakpointList.length == 0) {
            // Add a new list item to the bottom of the list
            var params = type == 'breakpoint'
                            ? {condition: bp.code, conditionEnabled: ! bp.inactive}
                            : {action: bp.code, actionEnabled: ! bp.inactive};
            params.filename = bp.filename;
            params.lineno = bp.line;
            $breakpointsList.append( breakpointPaneItemTemplate(params));
        }
    }

    function markCodePaneLineNumbersForBPActions(type, bplist, $codePane) {
        var all_classes = type + ' conditional-' + type + ' inactive-'+type;

        bplist.forEach(function(bp) {
            var new_classes = type;

            if (bp.code != '1') {
                new_classes += ' conditional-'+type;
            }
            if (bp.inactive) {
                new_classes += ' inactive-'+type;
            }
            // Update code pane lines
            matchingLineElementsForBreakpoint(bp, $codePane)
                .removeClass(all_classes)
                .addClass(new_classes);
        });
    }

    function updateForChangedBPAction(type, bp) {
        markCodePaneLineNumbersForBPActions(type, [bp]);
        // Update breakpoint pane
        updateBreakpointPaneElementForChangedBPAction(type, bp);
    };

    this.markCodePaneLineNumbersForBreakpointsAndActions = function($codePane) {
        var filename = $codePane.attr('data-filename'),
            bpactions = { breakpoint: breakpoints[filename], action: actions[filename] };

        ['breakpoint','action'].forEach(function(type) {
            var bpaction_list = [];
            for (var line in bpactions[type]) {
                bpaction_list.push(bpactions[type][line]);
            }
            markCodePaneLineNumbersForBPActions(type, bpaction_list, $codePane);
        });
    };

    function storeCreatedBPAction(type, bp) {
        var storage = type === 'breakpoint' ? breakpoints : actions,
            filename = bp.filename;

        if (! storage[filename]) {
            storage[filename] = {};
        }
        storage[filename][bp.line] = bp;
    }

    function createBPAction(type, params) {
        var create_method = rest_interface[ type === 'breakpoint' ? 'createBreakpoint' : 'createAction' ];

        create_method.call(rest_interface, params)
            .done(function(data) {
                var bp = new Breakpoint(data);

                storeCreatedBPAction(type, bp);
                updateForChangedBPAction(type, bp);
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
            removeBPAction('breakpoint',filename, line);
        } else {
            createBPAction('breakpoint', {filename: filename, line: line, code: '1'})
        }
    }

    // synchronize our list of breakpoints/actions with the debugged program
    this.sync = function() {
        var original_bpactions = { breakpoint: breakpoints, action: actions },
            new_bpactions = { breakpoint: {}, action: {} };

        function previously_existed(stored, filename, line) {
            return stored[filename] && stored[filename][line];
        }

        function copy_to_permanent(perm, temp, filename, line) {
            var bp = temp[filename][line];
            delete temp[filename][line];
            if (! perm[filename]) {
                perm[filename] = {};
            }
            perm[filename][line] = bp;
            return bp;
        }

        ['breakpoint','action'].forEach(function(bpType) {
            var getter_method = rest_interface[ bpType === 'breakpoint' ? 'getBreakpoints' : 'getActions' ];
            getter_method.call(rest_interface)
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert('Getting ' + bpType +' failed: ' + error_thrown);
                })
                .done(function(bpaction_list) {
                    bpaction_list.forEach(function(bp_params) {
                        if (previously_existed(original_bpactions[bpType], bp_params.filename, bp_params.line)) {
                            var bp = copy_to_permanent(new_bpactions[bpType], original_bpactions[bpType], bp_params.filename, bp_params.line),
                                changed = (bp.code != bp_params.code) || (bp.inactive != bp_params.inactive);
                            if (changed) {
                                updateForChangedBPAction(bpType, bp);
                            }

                        } else {
                            var bp = new Breakpoint(bp_params);
                            storeCreatedBPAction(bpType, bp);
                            updateForChangedBPAction(bpType, bp);
                        }
                    });
                });
        });

        // These are the object's main list of breakpoints/actions
        breakpoints = new_bpactions.breakpoint;
        actions = new_bpactions.action;

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
            isBreakpoint = $checkbox.closest('.bpaction-details').hasClass('breakpoint-details'),
            bpType = isBreakpoint ? 'breakpoint' : 'action',
            bp = isBreakpoint ? this.getBreakpoint(filename, line) : this.getAction(filename, line),
            changeMethod = rest_interface[ isBreakpoint ? 'changeBreakpoint' : 'changeAction' ].bind(rest_interface);

        if (bp === undefined) {
            // When we get here, the checkbox is already checked?!
            // we don't get a chance to preventDefault
            $checkbox.attr('checked', false);
            return;
        }

        changeMethod(bp.href, { inactive: state ? 0 : 1 })
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert('Changing ' + bpType + ' failed: '+ error_thrown);
                })
                .done(function() {
                    bp.inactive = $checkbox.is(':checked') ? 0 : 1;
                    updateForChangedBPAction(bpType, bp);
                });
    }

    function submitChangedBreakpointCondition(e) {
        e.preventDefault();
        var $form = $(e.target),
            $input = $form.find('input'),
            $container = $form.closest('.bpaction-code'),
            bp = e.data.bp,
            isBreakpoint = e.data.isBreakpoint,
            bpType = isBreakpoint ? 'breakpoint' : 'action',
            isNewBp = bp === undefined ? true : false,
            newCondition = $input.val();

        if (isNewBp) {
            createBPAction(bpType, {filename: e.data.filename, line: e.data.line, code: newCondition});
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
                    updateForChangedBPAction(bpType, bp);
                });
        }
    }

    function editBreakpointCondition(e) {
        var $elt = $(e.target),
            isBreakpoint = $elt.closest('.bpaction-details').hasClass('breakpoint-details'),
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
                        $elt.empty().append( breakpointConditionTemplate({ condition: bp ? bp.code : undefined }));
                    }
                });

        $elt.empty().append($form);
        $form.find('input').focus().select();
    }

    function removeFromBreakpointList(e) {
        var $target = $(e.target),
            $bpListItem = $target.closest('.breakpoint-pane-item'),
            filename = $bpListItem.attr('data-filename'),
            line = $bpListItem.attr('data-lineno');

        removeBPAction('breakpoint',filename, line);
        removeBPAction('action',filename, line);
    }

    $main_elt.on('click', '.code-line:not(.unbreakable) .lineno', breakableLineClicked.bind(this))
             .on('contextmenu', '.code-line:not(.unbreakable) .lineno', breakableLineRightClicked.bind(this))
             .on('click', clearBreakpointEditorPopover.bind(this))
             .on('click', 'input[type="checkbox"].bpaction-toggle', inactiveBreakpointCheckboxClicked.bind(this))
             .on('dblclick', '.bpaction-code', editBreakpointCondition.bind(this))
             .on('click', '.remove-breakpoint', removeFromBreakpointList.bind(this));
}

function Breakpoint(params) {
    var bp = this;
    ['filename','line','code','inactive','href'].forEach(function(key) {
        bp[key] = params[key];
    });
    return this;
}
