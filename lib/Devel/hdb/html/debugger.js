function Debugger(sel) {
    var dbg = this;
    this.elt = $(sel);

    this.filewindowDiv = this.elt.find('div#filewindow');
    this.stackDiv = this.elt.find('div#stack');

    // keys are filenames, values are lists of source lines
    this.files = {};  // keys are filenames, values are lists of source lines
    // keys are filenames, values are lists of booleans whether that line
    // is breakable
    this.breakable = {};

    // templates
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );
    this.programListingTemplate = Handlebars.compile( $('#program-listing-template').html() );

    // The step in, over, run buttons
    this.controlButtons = $('.control-button');

    this.initialize = function() {
        this.setProgramName();
        this.getStack(this.populateStackTabs.bind(this));

        this.elt.on('click', '.control-button', this.controlButtonClicked.bind(this));

        return this;
    };

    this.getStack = function(cb) {
        var dbg = this;
        $.ajax({url: 'stack',
            dataType: 'json',
            type: 'GET',
            success: function(data) {
                dbg.stack = new Stack(data);
                cb();
            }
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
                success: function() {
                    dbg.getStack( function() {
                        dbg.controlButtons.removeAttr('disabled');
                        dbg.populateStackTabs();
                    });
                }
            });
     };

    this.run = function() {

    };

    this.setProgramName = function() {
        $.ajax({url: 'program_name',
                dataType: 'html',
                type: 'GET',
                success: function(name) {
                    dbg.elt.find('li#program-name a').html(name);
                }
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
            var tabId = 'stack' + i;
            // TODO: add a tooltip to the tab that shows file/line
            // or function args
            var tab = dbg.navTabTemplate({  label: frame.subname,
                                            longlabel: frame.subroutine,
                                            tabId: tabId,
                                            filename: frame.filename,
                                            lineno: frame.line,
                                            active: firstTab
                                        });
            tabs.append(tab);

            var pane = $( dbg.navPaneTemplate({ tabId: tabId, active: firstTab }));
            panes.append(pane);
            dbg.loadElementWithProgramFile( pane, frame.filename, frame.line);

            firstTab = false;
        });
        tabs.find('a[rel="tooltip"]').tooltip();
    };

    this.loadElementWithProgramFile = function(element, filename, line) {
        var dbg = this;
        if (! this.files[filename]) {
            var d = $.Deferred(),
                programListingTemplate = dbg.programListingTemplate;

            this.files[filename] = d.promise();
            $.ajax({url: 'sourcefile',
                    method: 'GET',
                    data: { f: filename },
                    dataType: 'json',
                    success: function(data) {
                        var templateData = { rows: [] };
                            i = 1;
                        data.forEach(function(code) {
                            templateData.rows.push({ line: i++, code: code });
                        });
                        d.resolve( $(programListingTemplate(templateData)) );
                    }
                });
        }

        this.files[filename].done(function($html) {
            element.empty();
            var clone = $html.clone()
            clone.find('tr:nth-child('+line+')').addClass('active');
            element.append(clone);
        });

    };

    this.initialize();
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
}
Stack.prototype.forEachFrame = function(cb) {
    this.frames.forEach(cb);
}

// Represents one element in the stack
function StackFrame(f) {
    for (var key in f) {
        this[key] = f[key];
    }
}

