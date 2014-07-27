// A class to represent things that get stored in the 'events' list
// after hitting a control button
var ProgramEvent;
(function() {
    var templates = undefined;
    function fillTemplates() {
        if (!templates) {
            templates = {
                fork: Handlebars.compile($('#forked-child-modal-template').html() ),
                exit: Handlebars.compile($('#program-terminated-modal-template').html() ),
                exception: Handlebars.compile($('#uncaught-exception-modal-template').html() ),
                tracediff: Handlebars.compile($('#trace-diff-modal-template').html() )
            };
        }
    }

    ProgramEvent = function(params) {
        fillTemplates();
        if (! (params.type in templates)) {
            throw new Error('Unknown type of event: ' + params.type);
        }

        for (var k in params) {
            this[k] = params[k];
        }

        // an exception's 'value' is special
        if (this.type == 'exception') {
            this.value = PerlValue.parseFromEval(this.value);
        }

        var template = templates[this.type];
        this.render = function($container) {
            var $modal = $(template(this));

            $modal.appendTo($container)
                  .modal({ backdrop: true, keyboard: true, show: true })
                  .focus()
                  .on('hidden', function(e) {
                        $modal.remove();
                    });

            var d = $.Deferred();
            $modal.find('button').on('click', function(e) {
                var $target = $(e.currentTarget);
                d.resolve($target.val());
            });

            return d.promise();
        };

        return this;
    };
})();

