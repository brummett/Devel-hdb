function RestInterface(base_url) {
    var rest_interface = this;

    this.stack = function() {
        return this._GET('stack', undefined);
    };

    this.stackFrame = function(i) {
        return this._GET('stack/' + i);
    };

    this.stackFrameSignature = function(i, cb) {
        var request = this._HEAD('stack/' + i, undefined),
            d = $.Deferred();

        request.done(function(result, status, jqXHR) {
            var uuid = jqXHR.getResponseHeader('X-Stack-UUID'),
                line = jqXHR.getResponseHeader('X-Stack-Line');
            d.resolve(uuid, line);
        })
        .fail(function() { d.reject.apply(d, arguments); return false; });
        return d.promise();
    };

    this.programName = function() {
        return this._GET('program_name', undefined);
    };

    this.fileSourceAndBreakable = function(filename) {
        return this._GET('source/' + filename, undefined);
    };

    ['stepin','stepout','stepover','continue','exit'].forEach(function(action) {
        this[action] = function() {
            return this._POST(action, undefined);
        };
    }, this);

    this._GET = function(url, params) {
        return this._http_request('GET', url, params);
    };
    this._POST = function(url, params) {
        return this._http_request('POST', url, params);
    };
    this._DELETE = function(url, params) {
        return this._http_request('DELETE', url, params);
    };
    this._HEAD = function(url, params) {
        return this._http_request('HEAD', url, params);
    };

    function combined_url() {
        var str = base_url;
        for (var i = 0; i < arguments.length; i++) {
            str += '/' + arguments[i];
        }
        return str;
    }

    this._http_request = function(method, url, params) {
        var whole_url = combined_url(url);

        var ajax_params = {
                type: method,
                url: whole_url,
                dataType: 'json',
                success: cb,
                error: error_handler
        };

        if (params) {
            ajax_params.data = params;
        }

        return $.ajax(ajax_params);
    };

}
