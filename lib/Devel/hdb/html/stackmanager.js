function StackManager(messageHandler, changeCb) {
    this.stackFrames = [];
    this.stackFrameCount = -1;
    this.messageHandler = messageHandler;
    this.changeCb = changeCb;
    this.navTabTemplate = Handlebars.compile( $('#nav-tab-template').html() );
    this.navPaneTemplate = Handlebars.compile( $('#nav-pane-template').html() );

    messageHandler.addHandler('stack', this.stackUpdated.bind(this));
};

StackManager.prototype.stackUpdated = function(frames) {
    var minDepth = this.stackFrames.length < frames.length ? this.stackFrames.length : frames.length,
        i;

    for (i = 0; i < minDepth; i++) {
        s = new StackFrame(frames[i]);
        if (StackFrame.prototype.isDifferent(this.stackFrames[i], s)) {
            this.stackFrames[i] = s;
            this.changeCb(i, s, false);
        } else {
            this.changeCb(i, s, true);
        }
    }
    if (this.stackFrames[i] && (! frames[i])) {
        // Cached stackFrames still has more data
        // we've returned one or more frames
        for ( ; i < this.stackFrames.length; i++) {
            this.stackFrames[i] = undefined;
            this.changeCb(i, undefined, false);
        }
        this.stackFrames.length = frames.length;

    } else {
        // New stack has more frames than cached
        // we've stepped in one or more frames
        for ( ; i < frames.length; i++) {
            s = new StackFrame(frames[i]);
            this.stackFrames.push(s);
            this.changeCb(i, s, false);
        }
    }
};


// Represents one element in the stack
function StackFrame(f) {
    if (!f) {
        return undefined;
    }
    for (var key in f) {
        this[key] = f[key];
    }
};

StackFrame.prototype.isDifferent = function(f1, f2) {
    if( ( f1 ? 1 : 0 ) ^ ( f2 ? 1 : 0 ) ) {   // XOR
        return true;
    }

    return ((f1.package !== f2.package) 
            ||
        (f1.filename !== f2.filename)
            ||
        (f1.subroutine !== f2.subroutine)
    );
}
