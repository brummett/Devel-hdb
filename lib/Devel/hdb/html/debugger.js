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
    this.programListingTemplate = Handlebars.compile( $('#nav-pane-template').html() );

    this.initialize = function() {
        this.setProgramName();
        var s = new Stack(this.populateStackTabs.bind(this));

        return this;
    };

    this.run = function() {

    };

    this.loadFile = function(filename, cb) {
        
    };

    this.setProgramName = function() {
        $.ajax({url: 'program_name',
                dataType: 'html',
                type: 'GET',
                success: function(name) {
                    dbg.elt.find('li#program-name').html(name);
                }
            });
    };

    this.populateStackTabs = function(stack) {
        var i,
            dbg = this,
            tabs = this.stackDiv.find('ul.nav'),
            panes = this.stackDiv.find('div.tab-content'),
            firstTab = true;
    
        for (i = 0; i < stack.depth; i++) {
            stack.forEachFrame( function(frame, i) {
                var tabId = 'stack' + i;
                // TODO: add a tooltip to the tab that shows file/line
                // or function args
                var tab = dbg.navTabTemplate({ label: frame.subroutine + '()', tabId: tabId});
                tabs.apppend(tab);

                var pane = $( dbd.navPaneTemplate({ tabId: tabId }));
                dbg.loadElementWithProgramFile( pane, frame.filename, frame.line);

                if (firstTab) {
                    tab.addClass('active');
                    pane.addClass('active');
                    firstTab = false;
                }
            });
        }
    };

    this.loadElementWithProgramFile = function(element, filename, line) {
        var dbg = this;
        if (! this.files[filename]) {
            var d = $.Deferred();
            this.files[filename] = d.promise;
            $.ajax({url: 'sourcefile',
                    method: 'GET',
                    data: { f: filename },
                    dataType: 'json',
                    success: function(data) {
                        var templateData = [],
                            i = 1;
                        data.forEach(function(code) {
                            templateData.push({ lineno: i++, code: line});
                        });
                        d.resolve( dbg.programListingTemplate(templateData) );
                    }
                });
        }

        this.files[filename].done(function(html) {
            element.html(html);
        });

    };
}

// Represents the call stack in the debugged process
function Stack(cb) {
    var that = this;

    this.stack = [];

    $.ajax({url: 'stack',
            dataType: 'json',
            type: 'GET',
            success: function(data) {
                var i;
                for (i = 0; i < data.length; i++) {
                    that.stack.push(new StackFrame(data[i]));
                }
                that.depth = i;
                cb(that);
            }
        });
}
Stack.prototype.frame = function(i) {
    return this.stack[i];
}
Stack.prototype.forEachFrame = function(cb) {
    this.stack.forEach(cb);
}

// Represents one element in the stack
function StackFrame(f) {
    for (var key in f) {
        this[key] = f[key];
    }
}

