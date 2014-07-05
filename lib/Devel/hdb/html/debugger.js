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
        navTabContent: Handlebars.compile( $('#nav-tab-content-template').html() ),
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
}
