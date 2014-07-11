function BreakpointManager(rest_interface) {
    breakpoints     = {}; // keyed by filename, then by line number
    actions         = {};
    codePanes       = {}; // keyed by filename, elts are $codePanes

    this.forEachBreakpoint = function(cb) {
        
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

    this.removeBreakpoint = function(filename, line) {
        delete breakpoints[filename][line];
        notifyCodePanes('breakpointRemoved', filename, line);
    };

    this.changeAction = function(filename, line, code, inactive) {
        var bp = resolveForFilenameAndLine(actions, filename, line);
        bp.code = code;
        bp.inactive = inactive;
        notifyCodePanes('actionChanged', filename, bp);
    };

    this.removeAction = function(filename, line) {
        delete actions[filename][line];
        notifyCodePanes('actionRemoved', filename, line);
    };

    function filenameForCodePane($codePane) {
        $codePane.find('[data-filename]').attr('data-filename');
    }

    function markBreakpointsForCodePane($codePane) {
        var filename = filenameForCodePane($codePane);
        
    }

    this.codePaneAdded = function($codePane) {
        //var filename = filenameForCodePane($codePane);
        //codePanes[filename] ||= [];
        //codePanes[filename].push($codePane);

        //markBreakpointsForCodePane($codePane);
    };

    this.codePaneRemoved = function($codePane) {
        //var filename = filenameForCodePane($codePane);
        //delete codePanes[filename];
    };

    $(document).on('codePaneAdded', this.codePaneAdded.bind(this))
               .on('codePaneRemoved', this.codePaneRemoved.bind(this))
               .on('breakpointChanged', this.changeBreakpoint.bind(this))
               .on('breakpointRemoved', this.removeBreakpoint.bind(this))
               .on('actionChanged', this.changeAction.bind(this))
               .on('actionRemoved', this.removeAction.bind(this));
}

function Breakpoint(params) {
    var bp = this;
    ['filename','line','code','inactive'].forEach(function(key) {
        bp[key] = params[key];
    });
}

