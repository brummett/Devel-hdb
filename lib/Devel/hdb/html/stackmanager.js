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
    this.update = function(stack_depth) {
        var d = $.Deferred(),
            prev_frames_by_serial = {},
            waiting_on_frames = stack_depth;

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

        function update_frame_with_idx(i) {
            console.log('Getting info for stack frame '+i);
            rest_interface.stackFrameSignature(i)
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert("Couldn't get signature for frame "+i+": "+error_thrown);
                })
                .done(function(serial, lineno) {
                    if (serial in prev_frames_by_serial) {
                        // this frame existed before
                        var prev_frame = prev_frames_by_serial[serial],
                            old_frameno = prev_frame.frameno;
                        new_frames[i] = prev_frame;
                        prev_frame.line = lineno;
                        prev_frame.frameno = i;
                        d.notify(new_frames[i], old_frameno, i);
                        delete prev_frames_by_serial[serial];
                    } else {
                        // This is a new frame that did not exist before
                        rest_interface.stackFrame(i)
                            .done(function(new_frame) {
                                var frame_obj = _insert_frame_from_new(i, new_frame, new_frames);
                                d.notify(new_frames[i], null, i);
                            });
                    }
                });
        };

        d.progress(function() {
            if (--waiting_on_frames === 0) {
                finalize();
            }
        });

        for (var i = 0; i < stack_depth; i++) {
            update_frame_with_idx(i); // Kick off the update
        }

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
    for(var i = 0; i < params.args.length; i++) {
        args[i] = PerlValue.parseFromEval(params.args[i]);
    }

    if (this.wantarray === null) {
        this.sigil = '';
    } else if (this.wantarray) {
        this.sigil = '@';
    } else {
        this.sigil = '$';
    }
}
