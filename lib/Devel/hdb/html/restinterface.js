function RestInterface(base_url, error_handler) {

    if (! error_handler) {
        error_handler = makeErrorHandler().bind(this);
    }

    this.stack = function(cb) {
        this._GET('stack', undefined, function(a,b,c,d,e,f) {
            cb();
        });
    };

    this.programName = function(cb) {
        this._GET('program_name', undefined, function(result, status, jqXHR) {
            cb(result.program_name);
        });
    };

    this._GET = function(url, params, cb) {
        this._http_request('GET', url, params, cb);
    };
    this._POST = function(url, params, cb) {
        this._http_request('POST', url, params, cb);
    };
    this._DELETE = function(url, params, cb) {
        this._http_request('DELETE', url, params, cb);
    };
    this._HEAD = function(url, params, cb) {
        this._http_request('HEAD', url, params, cb);
    };

    function combined_url() {
        var str = base_url;
        for (var i = 0; i < arguments.length; i++) {
            str += '/' + arguments[i];
        }
        return str;
    }

    this._http_request = function(method, url, params, cb) {
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

        $.ajax(ajax_params);
    };

    function makeErrorHandler() {
        return function(jqxhr, text_status, error_thrown) {
            alert("A restInterface error occured: " + error_thrown.message);
        };
    }
}
