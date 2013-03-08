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

    // Keys are expression strings, values are the div they display in
    this.watchedExpressions = {};

    this.programTerminated = false;

    // templates
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navTabContentTemplate = Handlebars.compile( $('#nav-tab-content-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );
    this.watchedExpressionTemplate = Handlebars.compile( $('#watched-expr-template').html() );
    Handlebars.registerHelper('ifDefined', function(val, options) {
        if ((val !== undefined) && (val !== null) && (val !== '')) {
            return options.fn(this)
        } else {
            return options.inverse(this);
        }
    });
    this.breakpointRightClickMenu = Handlebars.compile( $('#breakpoint-right-click-template').html() );

    // The step in, over, run buttons
    this.controlButtons = $('.control-button');

    this.initialize = function() {
        this.messageHandler.addHandler('program_name', this.programNameUpdated.bind(this))
                            .addHandler('termination', this.programWasTerminated.bind(this))
                            .addHandler('evalresult', this.watchExpressionResult.bind(this))
                            .addHandler('hangup', this.hangup.bind(this));

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
        this.elt.on('click', 'tr:not(.unbreakable) td.lineno span',
                    this.breakableLineClicked.bind(this));
        this.elt.on('contextmenu', 'tr:not(.unbreakable) td.lineno',
                    this.breakableLineRightClicked.bind(this));
        this.elt.on('click', '.breakpoint-condition,.action',
                    this.editBreakpointCondition.bind(this));

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
                dbg.watchDiv.css({  width: width-1,
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

    // Toggle the breakpoint on a line
    this.breakableLineClicked = function(e) {
        var $elt = $(e.target),
            filename = $elt.closest('div.tab-pane').attr('data-filename'),
            lineno = $elt.closest('tr').attr('data-line'),
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
    this.breakpointsForPane = function(e, bp_hash) {
        // bp_hash is a hash of { line: { condition: cond, action: act } }
        // 'this' in this function is the .program-code table with the program code

        var $codeTable = $( this ),
            line;

        for (line in bp_hash) {
            var condition = bp_hash[line].condition,
                action = bp_hash[line].action,
                sel = 'tr:nth-child('+line+')';
                lineElt = $codeTable.find('tr:nth-child('+line+')');

            lineElt.removeClass('breakpoint conditional-breakpoint inactive-breakpoint bpaction');
            if (condition === '0') {
                lineElt.addClass('inactive-breakpoint');
            } else if (condition === '1') {
                lineElt.addClass('breakpoint');
            } else if (condition) {
                lineElt.addClass('conditional-breakpoint');
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
        this._drawBreakpointMenu($elt);
    };
    this._drawBreakpointMenu = function($elt) {
        var filename = $elt.closest('div.tab-pane').attr('data-filename'),
            lineno = $elt.closest('tr').attr('data-line'),
            bp = this.breakpointManager.get(filename, lineno),
            menu = this.breakpointRightClickMenu({  condition: bp.condition,
                                                    action: bp.action,
                                                    filename: filename,
                                                    lineno: lineno});
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
    // When the user clicks a breakpoint condition or action in the
    // breakpoint context menu
    this.editBreakpointCondition = function (e) {
        var $elt = $(e.currentTarget),
            filename = $elt.attr('data-filename'),
            lineno = $elt.attr('data-lineno'),
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
                dbg._drawBreakpointMenu(dbg.breakpointPopover);
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

    // Set the given line "active" (hightlited) and scroll it into view
    // if necessary
    this.setCurrentLineForCodeTable = function(codeTable, line) {
        codeTable.find('tr').removeClass('active');
        var activeLine = codeTable.find('tr:nth-child('+line+')').addClass('active');
        if (activeLine.length === 0) {
            // When the program terminates, line is 0 and activeLine.length === 0
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
            container.scrollTo(activeLine, { over: -2 });  // Leave 2 lines at the top
        }
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
            codePane = panes.find('.program-code-container:nth-child('+ (i+1) + ')'),
            dbg = this,
            html = '';

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

        if (isSameFrame) {
            // same package and filename for the current frame
            if (i === 0) {
                // just update the currently active line
                var codeTable = codePane.find('table.program-code');
                this.setCurrentLineForCodeTable(codeTable, line);
            }
            return;
        }

        html = this.navPaneTemplate({   tabId: tabId,
                                        filename: filename,
                                        active: i === 0 });
        if (codePane.length === 0) {
            codePane = $(html).appendTo(panes);
            dbg._setElementHeight.call(codePane);
        } else {
            codePane.empty();
        }
        this.fileManager.loadFile(filename)
            .done(function($elt) {
                var $copy = $elt.clone();
                $copy.appendTo(codePane)
                    .bind('breakpoints-updated', dbg.breakpointsForPane);
                    //.find('tr:nth-child('+line+')').addClass('active');
                dbg.setCurrentLineForCodeTable($copy, line);
                dbg.breakpointManager.markBreakpoints(filename, $copy);
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
        debugger;
        alert('Error from ajax call.  Status "' + status +'" error "'
                +error+'": '+xhdr.responseText);
    };

    this.initialize();

    function BreakpointManager() {
        this.breakpoints    = {};  // keyed by filename, then by line number
        this.messageHandler = dbg.messageHandler;

        this.breakpointUpdated = function(data) {
            var filename    = data.filename,
                line        = data.lineno,
                condition   = data.condition;
                action      = data.action;

            var breakpoint = {};
            breakpoint[line] = {};

            if (condition) {
                breakpoint[line].condition = condition;
            }
            if (action) {
                breakpoint[line].action = action;
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
            }
            if ('action' in params) {
                this.breakpoints[filename][lineno].action = params.action;
                postData.a = params.action;
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

