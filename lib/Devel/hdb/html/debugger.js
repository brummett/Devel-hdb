function Debugger(sel) {
    var dbg = this;
    this.elt = $(sel);

    this.filewindowDiv = this.elt.find('div#filewindow');
    this.stackDiv = this.elt.find('div#stack');

    // keys are filenames, values are lists of source lines
    this.files = {};  // keys are filenames, values are lists of source lines

    // keys are filenames then line number.  Value is the breakpoint object
    this.breakpoints = new BreakpointManager();

    // Keys are expression strings, values are the div they display in
    this.watchedExpressions = {};

    this.programTerminated = false;

    // templates
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );
    this.programListingTemplate = Handlebars.compile( $('#program-listing-template').html() );
    this.watchedExpressionTemplate = Handlebars.compile( $('#watched-expr-template').html() );
    this.watchedValueTemplate = Handlebars.compile( $('#watched-value-template').html() );

    // The step in, over, run buttons
    this.controlButtons = $('.control-button');

    this.messageHandler = new MessageHandler();

    this.stackUpdated = function(data) {
        this.stack = new Stack(data);
        dbg.populateStackTabs();
    };

    this.initialize = function() {
        this.messageHandler.addHandler('stack', this.stackUpdated.bind(this))
                            .addHandler('breakpoint', this.breakpointUpdated.bind(this))
                            .addHandler('program_name', this.programNameUpdated.bind(this))
                            .addHandler('sourcefile', this.sourceFileUpdated.bind(this))
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
        this.elt.on('click', 'button.remove-watched-expression',
                    this.removeWatchExpression.bind(this));

        $('button#add-watch-expr').click(this.addWatchExpression.bind(this));

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
            bp = this.breakpoints.get(filename, lineno),
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
    this.breakpointUpdated = function(data) {
        var filename = data.filename,
            lineno = data.lineno,
            condition = data.condition,
            elts = this.elt.find('div[data-filename="' + filename + '"] '
                                + 'table.program-code tr:nth-child('+ lineno + ')');

        this.breakpoints.set({ filename: filename, lineno: lineno, condition: condition});
        if (condition) {
            if (condition === '1') {
                elts.removeClass('condition-breakpoint inactive-breakpoint')
                    .addClass('breakpoint');
            } else {
                elts.removeClass('breakpoint inactive-breakpoint')
                    .addClass('conditional-breakpoint');
            }
        } else if (condition === '0') {
            elts.removeClass('breakpoint conditional-breakpoint')
                .addClass('inactive-breakpoint');
        } else {
            elts.removeClass('breakpoint condition-breakpoint inactive-breakpoint');
        }
    };

    // Context menu for breakpoints
    this.breakableLineRightClicked = function(e) {

    };

    this.getStack = function(cb) {
        $.ajax({url: 'stack',
            dataType: 'json',
            type: 'GET',
            success: this.messageHandler.consumer,
            error: this.ajaxError
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

    this.populateStackTabs = function() {
        var i,
            dbg = this,
            tabs = this.stackDiv.find('ul.nav'),
            panes = this.stackDiv.find('div.tab-content'),
            firstTab = true;

        // First clear out tabs that are already there
        tabs.empty();
        panes.empty();
    
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

            var paneTmplData = { tabId: tabId, active: firstTab, filename: filename };
            if (dbg.files[filename]) {
                paneTmplData.html = dbg.files[filename];
            } else {
                dbg.requestSourceFile(filename);
            }
            var codePane = $( dbg.navPaneTemplate( paneTmplData ) );

            codePane.appendTo(panes)
                .bind('file-loaded', function() {
                    $(this).find('tr:nth-child('+line+')').addClass('active');
                })
                .find('tr:nth-child('+line+')').addClass('active');
            dbg._setElementHeight.bind(codePane)();

            dbg.highliteBreakpointsInCode(codePane);

            firstTab = false;
        });
        tabs.find('a[rel="tooltip"]').tooltip();
    };

    this.highliteBreakpointsInCode = function(pane) {
        var filename = pane.attr('data-filename'),
            bpThisFile = this.breakpoints[filename],
            lineno;

        //pane.find('tr').removeClass('breakpoint conditional-breakpoint inactive-breakpoint');
        if (bpThisFile) {
            for (lineno in bpThisFile) {
                var tr = pane.find('tr:nth-child('+lineno+')');
                if (bpThisFile[lineno] === '1') {
                   tr.addClass('breakpoint');
                } else if (bpThisFile[lineno] === '0') {
                    tr.addClass('inactive-breakpoint');
                } else {
                    tr.addClass('conditional-breakpoint');
                }
            }
        }
    };

    this.requestSourceFile = function(filename) {
        this.files[filename] = undefined;
        $.ajax({url: 'sourcefile',
                type: 'GET',
                data: { f: filename },
                success: this.messageHandler.consumer,
                error: this.ajaxError
        });
    };
    this.sourceFileUpdated = function(data) {
        var filename = data.filename;

        var $elts = this.elt.find('div[data-filename="' + filename + '"]');
        var templateData = { rows: [] },
            i = 1;
        data.lines.forEach(function(line) {
            templateData.rows.push({ line: i++, code: line[0], unbreakable: !line[1] });
        });
        this.files[filename] = this.programListingTemplate( templateData );
        this.elt.find('div.program-code-container[data-filename="'+filename+'"]')
                .empty()
                .append(this.files[filename])
                .trigger('file-loaded');

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
        var thisDiv = this.watchedExpressions[data.expr];
        if (thisDiv) {
            if ((data.result === undefined) || (data.result === null)) {
                delete data.result;
                data.undef = true;
            }
            var p = new PerlValue(data.result);
            thisDiv.find('.value').empty().append(p.render());
        }
    };
    this.removeWatchExpression = function(e) {
        var expr = $(e.target).closest('div').attr('data-expr'),
            div = this.watchedExpressions[expr];

        delete this.watchedExpressions[expr];
        div.remove();
    };
    this.addWatchExpression = function(e) {
        var newExprInput = $('<form><input type="text" name="expr"></form>'),
            watchExpressions = this.elt.find('#watch-expressions'),
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
        var that = this;
        this.exists = function(filename, lineno) {
            if ((filename in this) && (lineno in this[filename])) {
                return true;
            } else {
                return false;
            }
        };
        this.get = function(filename, lineno) {
           if (filename in this) {
                return this[filename][lineno];
            } else {
                return undefined;
            }
        };
        this.set = function(params) {
            var filename = params.filename,
                lineno = params.lineno,
                condition = ('condition' in params) ? params.condition : 1;

            if ((condition === undefined) || (condition === null)) {
                if (filename in this) {
                    delete this[filename][lineno];
                }
            } else {
                if (! (filename in this)) {
                    this[filename] = {};
                }
                this[filename][lineno] = condition;
            }
        };
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

