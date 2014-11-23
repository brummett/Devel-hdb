function RestInterface(base_url) {
    var rest_interface = this;

    this.stack = function() {
        return this._GET('stack', undefined);
    };

    this.stackNoArgs = function() {
        return this._GET('stack?exclude_sub_params=1');
    };

    this.stackFrame = function(i) {
        return this._GET('stack/' + i);
    };

    this.stackFrameNoArgs = function(i) {
        return this._GET('stack/' + i + '?exclude_sub_params=1');
    };

    this.stackFrameSignature = function(i, cb) {
        var request = this._HEAD('stack/' + i, undefined),
            d = $.Deferred();

        request.done(function(result, status, jqXHR) {
            var serial = jqXHR.getResponseHeader('X-Stack-Serial'),
                line = jqXHR.getResponseHeader('X-Stack-Line');
            d.resolve(serial, line);
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

    this.getVarAtLevel = function(varname, level) {
        var url = 'getvar/' + level + '/' + encodeURIComponent(varname);
        return this._GET(url, undefined);
    };

    this.createBreakpoint = function(params) {
        return this._POST('breakpoints', params);
    };

    this.deleteBreakpoint = this.deleteAction = function(id) {
        return this._DELETE(id);
    };

    this.createAction = function(params) {
        return this._POST('actions', params);
    };

    this.getBreakpoints = function() {
        return this._GET('breakpoints');
    };

    this.getActions = function() {
        return this._GET('actions');
    };

    this.changeBreakpoint = this.changeAction = function(href, params) {
        return this._POST(href, params);
    };

    this.eval = function(expr, wantarray) {
        var d = $.Deferred();
        return this._POST('eval', { code: expr, wantarray: wantarray });
    };

    this.subInfo = function(subname) {
        return this._GET('subinfo/' + subname);
    };

    this.packageInfo = function(pkg) {
        return this._GET('packageinfo/' + pkg);
    };

    this.loadConfig = function(filename) {
        return this._POST('loadconfig/' + filename);
    };

    this.saveConfig = function(filename) {
        return this._POST('saveconfig/' + filename);
    };

    ['stepin','stepout','stepover','continue','exit'].forEach(function(action) {
        this[action] = function() {
            return this._POST(action, undefined);
        };
    }, this);

    this.getWatchpoints = function() {
        return this._GET('watchpoints');
    };

    this.createWatchpoint = function(expr) {
        return this._PUT('watchpoints/' + expr);
    };

    this.deleteWatchpoint = function(expr) {
        return this._DELETE('watchpoints/' + expr);
    };

    this._GET = function(url, params) {
        return this._http_request('GET', url, params);
    };
    this._POST = function(url, params) {
        return this._http_request('POST', url, params);
    };
    this._PUT = function(url, params) {
        return this._http_request('PUT', url, params);
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
            if (! (arguments[i].charAt(0) == '/')) {
                str += '/';
            }
            str += arguments[i];
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
            ajax_params.data = JSON.stringify(params);
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
