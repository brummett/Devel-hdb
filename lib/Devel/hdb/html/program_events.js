// A class to represent things that get stored in the 'events' list
// after hitting a control button
function ProgramEvent(params) {
    if (arguments.length == 0) {
        return;
    }

    if (params.type in ProgramEvent) {
        var o = new ProgramEvent[type];
        o.type = params.type;
        return o;
    }
    throw new Error('Unknown type of event: ' + type);
}

ProgramEvent.exit = function(params) {
    this.exit_code = params.value;
};
ProgramEvent.exit.prototype = new ProgramEvent();

ProgramEvent.fork = function(params) {
    this.pid = params.pid;
    this.href = params.href;
    this.continue_href = params.continue_href;

};
ProgramEvent.fork.prototype = new ProgramEvent();

ProgramEvent.exception = function(params) {
    this.package = params.package;
    this.subroutine = params.subroutine;
    this.filename = params.filename;
    this.line = params.line;
    this.value = PerlValue.parseFromEval(params.value);
}
ProgramEvent.exception.prototype = new ProgramEvent();
