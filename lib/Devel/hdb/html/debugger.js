function Debugger(sel) {
    var dbg = this;
    var $elt = this.$elt = $(sel);

    this.filewindowDiv = $elt.find('div#filewindow');
    this.stackDiv = $elt.find('div#stack');
    this.watchDiv = $elt.find('div#watch-expressions');

    // templates
    Handlebars.registerHelper('ifDefined', function(val, options) {
        if ((val !== undefined) && (val !== null) && (val !== '')) {
            return options.fn(this)
        } else {
            return options.inverse(this);
        }
    });
    Handlebars.registerPartial('breakpoint-condition-template', $('#breakpoint-condition-template').html() );
    Handlebars.registerPartial('breakpoint-action-template', $('#breakpoint-action-template').html() );
    Handlebars.registerPartial('breakpoint-right-click-template', $('#breakpoint-right-click-template').html() );
    this.templates = {
        fileTab: Handlebars.compile( $('#file-tab-template').html() ),
        navTab: Handlebars.compile( $('#nav-tab-template').html() ),
        navPane: Handlebars.compile( $('#nav-pane-template').html() ),
        watchedExpression: Handlebars.compile( $('#watched-expr-template').html() ),
        currentSubAndArgs: Handlebars.compile( $('#current-sub-and-args-template').html() ),
        breakpointRightClickMenu: Handlebars.compile( $('#breakpoint-right-click-template').html() ),
        breakpointCondition: Handlebars.compile( $('#breakpoint-condition-template').html() ),
        breakpointAction: Handlebars.compile( $('#breakpoint-action-template').html() ),
        breakpointListItem: Handlebars.compile( $('#breakpoint-list-item-template').html() ),
        forkedChildModal: Handlebars.compile($('#forked-child-modal-template').html() ),
        saveLoadBreakpointsModal: Handlebars.compile($('#save-load-breakpoints-modal-template').html() ),
        programTerminatedModal: Handlebars.compile($('#program-terminated-modal-template').html() ),
        subPickerTemplate: Handlebars.compile($('#sub-picker-template').html() ),
        traceDiffModal: Handlebars.compile($('#trace-diff-modal-template').html() )
    };

    // The step in, over, run buttons
    this.controlButtons = $('.control-button');

    this.restInterface = new RestInterface('');

    this.stackFrameChanged = function(frame_obj, old_frameno, new_frameno) {
        var $tabs = this.stackDiv.find('ul.nav'),
            $tab = $tabs.find('#tab-' + frame_obj.uuid),
            $panes = this.stackDiv.find('div.tab-content'),
            $codePane = $panes.find('#pane-' + frame_obj.uuid);

        var insertStackFrameForLevel = function($elt, frameno) {
            var mapper = function() { return [ this, this.getAttribute('data-frameno') ]; },
                sorter = function(a,b) { return ( a[1] - b[1] ) },
                unmapper = function(a) { return a[0] },
                tab_elts_in_frame_order = $tabs.children().get().map(mapper).sort(sorter).map(unmapper),
                pane_elts_in_frame_order = $panes.children().get().map(mapper).sort(sorter).map(unmapper),
                elt_frameno = $elt.attr('data-frameno'),
                i;

            if (tab_elts_in_frame_order.length == 0
                || frameno > tab_elts_in_frame_order[ tab_elts_in_frame_order.length - 1].attr('data-frameno')
            ) {
                // This new one goes after the last one
                $tabs.append($elt);
            } else {
                for(i = 0; i < tab_elts_in_frame_order.length; i++) {
                    if (elt_frameno < tab_elts_in_frame_order[i].attr('data-frameno')) {
                        $elt.insertBefore(tab_elts_in_frame_order[i]);
                        break;
                    }
                }
            }
        };

        if (new_frameno === undefined) {
            // a frame got removed
            $tab.remove();
            $codePane.remove();

        } else if (old_frameno == undefined) {
            // This is a brand new frame
            $tab = $( dbg.templates.navTab({
                        uuid: frame_obj.uuid,
                        frameno: new_frameno,
                        longlabel: frame_obj.subroutine,
                        label: frame_obj.subname,
                        filename: frame_obj.filename,
                        lineno: frame_obj.line,
                        wantarray: frame_obj.sigil
                    }));
            insertStackFrameForLevel($tab, new_frameno);

        } else if (old_frameno == new_frameno) {
            // just the line got updated for this frame

            // update the tab tooltip
            var title = $tab.prop('title');
            title.replace(/\d+$/, frame_obj.line);
            $tab.prop('title', title);

            // Update the line in the code pane

        } else {
            // the frame got moved in the stack to a new depth
            $tab.detach();
            $tab.attr('data-frameno', new_frameno);
            insertStackFrameForLevel($tab, new_frameno);

        }
    };

    this.run = function() {

    };

    // Initialization
    this.restInterface.programName(function(program_name) {
        $elt.find('li#program-name a').html(program_name);
        dbg.programName = name;
    });

    this.restInterface.stack(function(stack) {
        var a = stack;
        1;
    });

    this.stackManager = new StackManager(this.restInterface, this.stackFrameChanged.bind(this));
}
