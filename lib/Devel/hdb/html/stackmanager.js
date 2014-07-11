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
            frames_by_uuid = {},
            waiting_on_frames = frames.length;

        for (var i = 0; i < frames.length; i++) {
            var uuid = frames[i].uuid;
            frames_by_uuid[uuid] = frames[i];
        }

        var new_frames = [];

        var update_frame_with_idx = function(i) {
            rest_interface.stackFrameSignature(i)
                .done(function(uuid, lineno) {
                    if (uuid === undefined) {
                        // Got to the end of the stack
                        frames = new_frames;
                        d.resolve(frames);

                    } else if (uuid in frames_by_uuid) {
                        // this frame existed before
                        new_frames[i] = frames_by_uuid[uuid];
                        if (frames_by_uuid[uuid].line != lineno) {
                            // The line changed
                            old_frameno = new_frames[i].line;
                            new_frames[i].line = lineno;
                            d.notify(new_frames[i], old_frameno, i);
                        }
                        delete frames_by_uuid[uuid];

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

                    if (--waiting_from_frames == 0) {
                        // Got responses from all the stack frames we had before.
                        // Anything else left in frames_by_uuid are gone
                        for (var uuid in frames_by_uuid) {
                            if (frames_by_uuid.hasOwnProperty(uuid)) {
                                d.notify(frames_by_uuid[uuid], frames_by_uuid[uuid].frameno, undefined);
                            }
                        }
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
