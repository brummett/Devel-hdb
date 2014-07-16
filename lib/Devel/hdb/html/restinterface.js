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
        .fail(function() {
            d.reject.apply(d, arguments);
        });
        return d.promise();
    };

    this.programName = function() {
        var d = $.Deferred();
        var result = this._GET('program_name', undefined);
        result.done(function(data) {
            d.resolve(data.program_name);
        });
        return d;
    };

    this.fileSourceAndBreakable = function(filename) {
        return this._GET('source/' + filename, undefined);
    };

    this.exit = function() {
        return this._POST('exit', undefined);
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
        if (this._is_disconnected()) {
            return $.Deferred().promise();
        }

        var whole_url = combined_url(url);

        var ajax_params = {
                type: method,
                url: whole_url,
                dataType: 'json',
        };

        if (params) {
            ajax_params.data = params;
        }

        return $.ajax(ajax_params);
    };

    this.disconnect = function() {
        base_url = null;
    };

    this._is_disconnected = function() {
        return base_url == null;
    };

}
