function Debugger(sel) {
    var dbg = this;
    this.elt = $(sel);

    this.filewindowDiv = this.elt.find('div#filewindow');
    this.stackDiv = this.elt.find('div#stack');

    this.messageHandler = new MessageHandler();

    // keys are filenames, values are jQuery objects for the HTML
    // without breakpoints or active line
    this.fileManager = new FileManager(this.messageHandler);

    this.codePanes = {};  // All the code window panes loaded by filename

    // keys are filenames then line number.  Value is the breakpoint object
    this.breakpointManager = new BreakpointManager();

    // Keys are expression strings, values are the div they display in
    this.watchedExpressions = {};

    this.programTerminated = false;

    // templates
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );
    this.watchedExpressionTemplate = Handlebars.compile( $('#watched-expr-template').html() );
    this.watchedValueTemplate = Handlebars.compile( $('#watched-value-template').html() );

    // The step in, over, run buttons
    this.controlButtons = $('.control-button');

    this.stackUpdated = function(data) {
        this.stack = new Stack(data);
        dbg.populateStackTabs();
    };

    this.initialize = function() {
        this.messageHandler.addHandler('stack', this.stackUpdated.bind(this))
                            .addHandler('program_name', this.programNameUpdated.bind(this))
                            .addHandler('termination', this.programWasTerminated.bind(this))
                            .addHandler('evalresult', this.watchExpressionResult.bind(this))
                            .addHandler('hangup', this.hangup.bind(this));

        this.getProgramName();
        this.getStack();

        this.elt.on('click', '.control-button', this.controlButtonClicked.bind(this));

        // events for breakpoints
        this.elt.on('click', 'tr:not(.unbreakable) td.lineno span',
                    this.breakableLineClicked.bind(this));
        this.elt.on('contextmenu', 'tr:not(.unbreakable) td.lineno',
                    this.breakableLineRightClicked.bind(this));

        this.elt.on('click', '.remove-watched-expression',
                    this.removeWatchExpression.bind(this));
        this.elt.on('dblclick', '.collapsable',
                    this.toggleCollapseWatchExpression.bind(this));


        $('#add-watch-expr').click(this.addWatchExpression.bind(this));

        $('.managed-height').each(this._setElementHeight);
        $(window).resize(this._setElementHeight);

        return this;
    };

    // Set the height so the the bottom of the element is the bottom of the
    // window.  This makes the scroll bar work for that element
    this._setElementHeight = function() {
        // this here is the jQuery element to set the height on
        $(this).css({'height': ((document.height)-$(this).offset().top)+'px'});
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

    // Toggle the breakpoint on a line
    this.breakableLineClicked = function(e) {
        var $elt = $(e.target),
            filename = $elt.closest('div.tab-pane').attr('data-filename'),
            lineno = $elt.closest('tr').attr('data-line'),
            bp = this.breakpointManager.get(filename, lineno),
            requestData = { f: filename, l: lineno };

        requestData.c = bp ? null : 1;

        $.ajax({url: 'breakpoint',
                type: 'POST',
                dataType: 'json',
                data: requestData,
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    };

    // Triggered by the breakpoint manager whenever a breakpoint changes
    this.breakpointsForPane = function(e, bp_hash) {
        // bp_hash is a hash of line: condition
        // this in this function is the .program-code table with the program code

        var $codeTable = $( this ),
            line;

        for (line in bp_hash) {
            var condition = bp_hash[line],
                sel = 'tr:nth-child('+line+')';
                lineElt = $codeTable.find('tr:nth-child('+line+')');

            if (condition) {
                if (condition === '1') {
                    lineElt.removeClass('condition-breakpoint inactive-breakpoint')
                        .addClass('breakpoint');
                } else {
                    lineElt.removeClass('breakpoint inactive-breakpoint')
                        .addClass('conditional-breakpoint');
                }
            } else if (condition === '0') {
                lineElt.removeClass('breakpoint conditional-breakpoint')
                    .addClass('inactive-breakpoint');
            } else {
                lineElt.removeClass('breakpoint condition-breakpoint inactive-breakpoint');
            }
        }
    };

    // Context menu for breakpoints
    this.breakableLineRightClicked = function(e) {

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

    this.programNameUpdated = function(name) {
        this.elt.find('li#program-name a').html(name);
    };
    this.getProgramName = function() {
        $.ajax({url: 'program_name',
                dataType: 'json',
                type: 'GET',
                success: this.messageHandler.consumer,
                error: this.ajaxError
            });
    };

    this.clearStackTabs = function() {
        // Clear the HTML elements
        this.stackDiv.find('ul.nav').empty();
        this.stackDiv.find('div.tab-content').empty();

        // Remove saved stack codePanes already in the list
        for (filename in this.codePanes) {
            for (i = 0; i < this.codePanes[filename].length; i++) {
                if (this.codePanes[filename][i].__is_stack) {
                    this.codePanes[filename].splice(i, 1);
                    i--;
                }
            }
        }
    };

    this.populateStackTabs = function() {
        var i,
            dbg = this,
            tabs = this.stackDiv.find('ul.nav'),
            panes = this.stackDiv.find('div.tab-content'),
            firstTab = true,
            filename, i;

        this.clearStackTabs();
    
        dbg.stack.forEachFrame( function(frame, i) {
            var tabId = 'stack' + i,
                filename = frame.filename,
                line = frame.line,
                tab = dbg.navTabTemplate({  label: frame.subname,
                                            longlabel: frame.subroutine,
                                            tabId: tabId,
                                            filename: filename,
                                            lineno: line,
                                            active: firstTab
                                        });
            tabs.append(tab);

            var codePane = $( dbg.navPaneTemplate({    tabId: tabId,
                                                        active: firstTab,
                                                        filename: filename}) );
            codePane.appendTo(panes)
            dbg._setElementHeight.bind(codePane)();
            firstTab = false;

            dbg.fileManager.loadFile(filename)
                .done(function($elt) {
                    var $copy = $elt.clone();
                    $copy.appendTo(codePane)
                        .bind('breakpoints-updated', dbg.breakpointsForPane)

                        .find('tr:nth-child('+line+')').addClass('active');
                    dbg.breakpointManager.markBreakpoints(filename, $copy);
                });
        });
        tabs.find('a[rel="tooltip"]').tooltip();
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
        var expr = $(e.target).closest('div').attr('data-expr'),
            div = this.watchedExpressions[expr];

        delete this.watchedExpressions[expr];
        div.remove();
    };
    this.toggleCollapseWatchExpression = function(e) {
        var collapsable = $(e.target),
            toCollapse = collapsable.siblings('dl')
            e.preventDefault();

            toCollapse.toggle(100);
    };
    this.addWatchExpression = function(e) {
        var newExprInput = $('<form><input type="text" name="expr"></form>'),
            watchExpressions = this.elt.find('#watch-expressions-container'),
            dbg = this;

        watchExpressions.append(newExprInput).find('input').focus();

        newExprInput.submit(function(e) {
            var expr = newExprInput.find('input').val();
            expr = expr.replace(/^\s+|\s+$/g,''); // Remove leading and trailing spaces

            e.preventDefault();
            newExprInput.remove();

            if (dbg.watchedExpressions[expr]) {
                // Already watching this expr
                alert('Already watching '+expr);
            } else {
                var newExpr = $( dbg.watchedExpressionTemplate({ expr: expr }) );
                dbg.watchedExpressions[expr] = newExpr;
                watchExpressions.append(newExpr);
                dbg.refreshWatchExpression(expr);
            }


        });
    };

    this.ajaxError = function(xhdr, status, error) {
        debugger;
        alert('Error from ajax call.  Status "' + status +'" error "'+error+'"');
    };

    this.initialize();

    function BreakpointManager() {
        this.breakpoints = {};  // keyed by filename, then by line number
        this.messageHandler = dbg.messageHandler;

        this.breakpointUpdated = function(data) {
            var filename    = data.filename,
                line        = data.lineno,
                condition   = data.condition;

            if (condition) {
                if (! (filename in this.breakpoints)) {
                    this.breakpoints[filename] = {};
                }
                this.breakpoints[filename][line] = condition;
            } else {
                if (filename in this.breakpoints) {
                    delete this.breakpoints[filename][line];
                }
            }
            var breakpoint = {};  // JS dosen't have syntax for object literals
            breakpoint[line] = condition;  // with variable keys, so we have to name it
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
                return this.breakpoints[filename][lineno];
            } else {
                return undefined;
            }
        };
        this.set = function(params) {
            var filename = params.filename,
                lineno = params.lineno,
                condition = ('condition' in params) ? params.condition : 1;

            $.ajax({url: 'breakpoint',
                    type: 'POST',
                    data: { f: filename, l: lineno, c: condition },
                    success: this.messageHandler.consumer
                });
        };

        this.messageHandler.addHandler('breakpoint', this.breakpointUpdated.bind(this))
    };
}

// Represents the call stack in the debugged process
function Stack(frames) {
    var that = this;
    this.frames = [];
    this.depth = frames.length;

    frames.forEach(function(frame) {
        that.frames.push( new StackFrame(frame) );
    });
}
Stack.prototype.frame = function(i) {
    return this.frames[i];
};
Stack.prototype.forEachFrame = function(cb) {
    this.frames.forEach(cb);
};

// Represents one element in the stack
function StackFrame(f) {
    for (var key in f) {
        this[key] = f[key];
    }
}


// Routes incoming messages to the right place
function MessageHandler() {
    this.handlers = {};

    this.addHandler = function(type, cb) {
        this.handlers[type] = cb;
        return this;
    };

    this.handle = function(data) {
        var that=this;
        if ('forEach' in data) {
            data.forEach(function(message) {
                that.handlers[ message.type ]( message.data );
            });
        } else {
            that.handlers[ data.type ]( data.data );
        }
    };

    this.consumer = this.handle.bind(this);
}

