function Debugger(sel) {
    var dbg = this;
    this.elt = $(sel);

    this.filewindowDiv = this.elt.find('div#filewindow');
    this.stackDiv = this.elt.find('div#stack');

    // keys are filenames, values are lists of source lines
    this.files = {};  // keys are filenames, values are lists of source lines

    // keys are filenames then line number.  Value is the breakpoint object
    this.breakpoints = new BreakpointManager();

    // templates
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );
    this.programListingTemplate = Handlebars.compile( $('#program-listing-template').html() );

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
                            .addHandler('sourcefile', this.sourceFileUpdated.bind(this));

        this.getProgramName();
        this.getStack();

        this.elt.on('click', '.control-button', this.controlButtonClicked.bind(this));

        // events for breakpoints
        this.elt.on('click', 'tr:not(.unbreakable) td.lineno span',
                    this.breakableLineClicked.bind(this));
        this.elt.on('contextmenu', 'tr:not(.unbreakable) td.lineno',
                    this.breakableLineRightClicked.bind(this));

        return this;
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
                success: this.messageHandler.consumer
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
        var dbg = this;
        $.ajax({url: 'stack',
            dataType: 'json',
            type: 'GET',
            success: this.messageHandler.consumer
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
                method: 'GET',
                dataType: 'json',
                success: function(messages) {
                    dbg.messageHandler.consumer(messages);
                    dbg.controlButtons.removeAttr('disabled');
                }
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
                success: this.messageHandler.consumer
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
            $( dbg.navPaneTemplate( paneTmplData ) )
                .appendTo(panes)
                .bind('file-loaded', function() {
                    $(this).find('tr:nth-child('+line+')').addClass('active');
                })
                .find('tr:nth-child('+line+')').addClass('active');

            firstTab = false;
        });
        tabs.find('a[rel="tooltip"]').tooltip();
    };
    this.requestSourceFile = function(filename) {
        this.files[filename] = undefined;
        $.ajax({url: 'sourcefile',
                method: 'GET',
                data: { f: filename },
                success: this.messageHandler.consumer
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

