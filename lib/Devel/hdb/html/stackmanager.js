function StackManager(rest_interface) {
    var frames = this.frames = [];

    // Return one particular frame
    this.frame = function(i) {
        return frames[i];
    };

    // Reload one particular frame
    this.reloadFrame = function(i) {
        var d = $.Deferred();
        rest_interface.stackFrame(i)
            .done(function(frame) {
                frames[i] = frame;
                d.resolve(frame);
            });
        return d.promise();
    };

    var _insert_frame_from_new = function(frameno, frame, frames) {
        frame.frameno = frameno;
        var frame_obj = new StackFrame(frame);
        frames[frameno] = frame_obj;
        return frame_obj;
    };

    // Reload all frames or initialize from new
    this.initialize = function() {
        var d = $.Deferred();
        frames.splice(0, frames.length); // Clear the list
        rest_interface.stack()
            .done(function(stack) {
                for(var i = 0; i < stack.length; i++) {
                    var frame_obj = _insert_frame_from_new(i, stack[i], frames);
                    d.notify(frame_obj, null, i);
                }
                d.resolve();
            });
        return d.promise();
    };

    // Update our representation of the stack efficiently using HEAD requests
    // when possible and GET requests when neessary
    this.update = function() {
        var d = $.Deferred(),
            prev_frames_by_serial = {};

        for (var i = 0; i < frames.length; i++) {
            var serial = frames[i].serial;
            prev_frames_by_serial[serial] = frames[i];
        }

        var new_frames = [];

        var finalize = function() {
            // Got responses from all the stack frames we had before.
            // Anything else left in prev_frames_by_serial are gone
            for (var serial in prev_frames_by_serial) {
                d.notify(prev_frames_by_serial[serial], prev_frames_by_serial[serial].frameno, null);
            }
            frames = new_frames;
            d.resolve();
        };

        function update_one_frame(frame, i) {
            var this_frame_serial = frame.serial;
            frame.frameno = i;
            new_frames[i] = frame;
            if (this_frame_serial in prev_frames_by_serial) {
                // this frame existed before
                var prev_frame = prev_frames_by_serial[this_frame_serial];

                if ((prev_frame.frameno !== frame.frameno)
                    || (prev_frame.line !== frame.line)
                ) {
                    d.notify(frame, prev_frame.frameno, i);  // Only notify if something changed
                }
                delete prev_frames_by_serial[this_frame_serial];

            } else {
                // This is a new frame that did not exist before
                d.notify(frame, null, i);
            }
        };

        rest_interface.stackNoArgs()
            .fail(function(jqxhr, text_status, error_thrown) {
                alert('Error getting stack: '+error_thrown);
            })
            .done(function(stackframes) {
                for (var i = (stackframes.length - 1); i >= 0; i--) {
                    var frame = new StackFrame(stackframes[i]);
                    update_one_frame(frame, i);
                };
                finalize();
            });
        return d.promise();
    };

    this.updateFrameWithArgs = function(frame) {
        var frameno = frame.frameno,
            d = $.Deferred();

        rest_interface.stackFrame(frameno)
            .fail(d)
            .done(function(new_frame_data) {
                var new_frame = new StackFrame(new_frame_data);
                frame.args = new_frame.args;
                d.resolve(frame);
            });

        return d.promise();
    };
}

function StackFrame(params) {
    var frame = this;
    ['package','filename','line','subroutine','subname','hasargs',
     'wantarray', 'evaltext', 'is_require','hints','bitmask','href',
     'evalfile','evalline','autoload','level','serial','frameno'
    ].forEach(function(key) {
        frame[key] = params[key];
    });

    var args = [];
    this.args = args;
    if(params.args) {
        for(var i = 0; i < params.args.length; i++) {
            args[i] = PerlValue.parseFromEval(params.args[i]);
        }
    }

    if (this.wantarray === null) {
        this.sigil = '';
    } else if (this.wantarray) {
        this.sigil = '@';
    } else {
        this.sigil = '$';
    }
}
