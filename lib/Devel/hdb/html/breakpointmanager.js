function BreakpointManager($main_elt, rest_interface) {
    var breakpoints = {}, // keyed by filename, then by line number
        actions     = {},
        $breakpoint_pane = $main_elt.find('#breakpoint-container');

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

    function notifyCodePanes(signal, filename, arg) {
        $('.breakpoint-listener[data-filename="'+filename+'"]')
            .trigger(signal, arg);
    }

    this.changeBreakpoint = function(filename, line, code, inactive) {
        var bp = resolveForFilenameAndLine(breakpoints, filename, line);
        bp.code = code;
        bp.inactive = inactive;

        notifyCodePanes('breakpointChanged', filename, bp);
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

    var updateForDeletedBreakpoint, updateForDeletedAction;
    (function() {
        var deleter = function(type) {
            var all_classes = type + ' conditional-' + type + ' inactive-'+type;
            return function(bp) {
                matchingLineElementsForBreakpoint(bp)
                    .removeClass(all_classes);
            };
        };

        updateForDeletedBreakpoint = deleter('breakpoint');
        updateForDeletedAction = deleter('bpaction');
    })();

    var updateForChangedBreakpoint, updateForChangedAction;
    (function() {
        var maker = function(type) {
            var all_classes = type + ' conditional-' + type + ' inactive-'+type;
            return function(bp, is_new) {
                var new_classes = type;
                if (bp.code != '1') {
                    new_classes += 'conditional-'+type;
                }
                if (bp.inactive) {
                    new_classes += 'inactive-'+type;
                }
                matchingLineElementsForBreakpoint(bp)
                    .removeClass(all_classes)
                    .addClass(new_classes);
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

    function insertCreatedBreakpoint(bp) {
        var filename = bp.filename,
            is_new = breakpoints[filename];

        if (! breakpoints[filename]) {
            breakpoints[filename] = {};
        }
        breakpoints[filename][bp.line] = bp;
        updateForChangedBreakpoint(bp, is_new);
    }

    this.createBreakpoint = function(params) {
        rest_interface.createBreakpoint(params)
            .done(function(data) {
                var bp = new Breakpoint(data);

                insertCreatedBreakpoint(bp);
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

    };

    // Remove the breskpoint popover if the user clicks outside of it
    var breakpointPopover;
    function clearBreakpointEditorPopover(e) {
        if (breakpointPopover && ($(e.target).closest('.popover').length == 0)) {
            e.preventDefault();
            e.stopPropogation();
            breakpointPopover.popover('destroy');
            breakpointPopover = undefined;
        }
    }

    $main_elt.on('click', '.code-line:not(.unbreakable) .lineno', breakableLineClicked.bind(this))
             .on('contextmenu', '.code-line:not(.unbreakable) .lineno', breakableLineRightClicked.bind(this))
             .on('click', clearBreakpointEditorPopover.bind(this));
}

function Breakpoint(params) {
    var bp = this;
    ['filename','line','code','inactive','href'].forEach(function(key) {
        bp[key] = params[key];
    });
    return this;
}
