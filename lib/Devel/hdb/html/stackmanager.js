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
                    d.notify(frame_obj, undefined, i);
                }
                d.resolve();
            });
        return d.promise();
    };

    // Update our representation of the stack efficiently using HEAD requests
    // when possible and GET requests when neessary
    this.update = function() {
        var d = $.Deferred(),
            prev_frames_by_uuid = {};

        for (var i = 0; i < frames.length; i++) {
            var uuid = frames[i].uuid;
            prev_frames_by_uuid[uuid] = frames[i];
        }

        var new_frames = [];

        var finalize = function() {
            // Got responses from all the stack frames we had before.
            // Anything else left in prev_frames_by_uuid are gone
            for (var uuid in prev_frames_by_uuid) {
                if (prev_frames_by_uuid.hasOwnProperty(uuid)) {
                    d.notify(prev_frames_by_uuid[uuid], prev_frames_by_uuid[uuid].frameno, undefined);
                }
            }
            d.resolve();
        };

        var update_frame_with_idx = function(i) {
            rest_interface.stackFrameSignature(i)
                .fail(function(jqxhr, text_status, error_thrown) {
                    if (jqxhr.status == 404) {
                        finalize();
                    } else {
                        alert("Couldn't get signature for frame "+i+": "+error_thrown);
                    }
                })
                .done(function(uuid, lineno) {
                    if (uuid === undefined) {
                        // Got to the end of the stack
                        frames = new_frames;
                        d.resolve(frames);

                    } else if (uuid in prev_frames_by_uuid) {
                        // this frame existed before
                        var prev_frame = prev_frames_by_uuid[uuid];
                        new_frames[i] = prev_frame;
                        if (prev_frames_by_uuid[uuid].line != lineno) {
                            // The line changed
                            old_frameno = prev_frame.frameno;
                            prev_frame.line = lineno;
                            prev_frame.frameno = i;
                            d.notify(new_frames[i], old_frameno, i);
                        }
                        delete prev_frames_by_uuid[uuid];

                        update_frame_with_idx(i + 1);  // recurse to get the next deeper frame

                    } else {
                        // This is a new frame that did not exist before
                        rest_interface.stackFrame(i)
                            .done(function(new_frame) {
                                var frame_obj = _insert_frame_from_new(i, new_frame, new_frames);
                                d.notify(new_frames[i], undefined, i);
                            });

                        update_frame_with_idx(i + 1); // recurse to get the next deeper frame
                    }
                });
        };

        update_frame_with_idx(0); // Kick off the update
        return d.promise();
    };
}

function StackFrame(params) {
    var frame = this;
    ['package','filename','line','subroutine','subname','hasargs',
     'wantarray', 'evaltext', 'is_require','hints','bitmask','href',
     'evalfile','evalline','autoload','level','uuid','frameno'
    ].forEach(function(key) {
        frame[key] = params[key];
    });

    var args = [];
    this.args = args;
    for(var i = 0; i < params.args.length; i++) {
        args[i] = PerlValue.parseFromEval(params.args[i]);
    }

    this.sigil = '';
    if (this.wantarray === 0) {
        this.sigil = '$';
    } else if (this.wantarray) {
        this.sigil = '@';
    }
}
