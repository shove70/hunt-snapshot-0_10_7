/*
 * Hunt - a framework for web and console application based on Collie using Dlang development
 *
 * Copyright (C) 2015-2017  Shanghai Putao Technology Co., Ltd
 *
 * Developer: HuntLabs
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module hunt.application.application;

import collie.codec.http.server.websocket;
import kiss.container.ByteBuffer;
import collie.codec.http.server;
import collie.codec.http;
import collie.bootstrap.serversslconfig;
import collie.utils.exception;
import hunt.cache;

public import kiss.event;
public import kiss.event.EventLoopGroup;

public import std.socket;
public import kiss.logger;
public import std.file;

import std.string;
import std.conv;
import std.stdio;
import std.uni;
import std.path;
import std.parallelism;
import std.exception;

import hunt.init;
import hunt.routing;
import hunt.application.dispatcher;
import hunt.security.acl.Manager;

public import hunt.http;
public import hunt.view;
public import hunt.i18n;
public import hunt.application.config;
public import hunt.application.middleware;
public import hunt.security.acl.Identity;


abstract class WebSocketFactory
{
    IWebSocket newWebSocket(const HTTPMessage header);
};


final class Application
{
    static @property Application getInstance()
    {
        if(_app is null)
        {
            _app = new Application();
        }

        return _app;
    }

    Address binded(){return addr;}

    /**
     Add a Router rule
     Params:
     method =  the HTTP method. 
     path   =  the request path.
     handle =  the delegate that handle the request.
     group  =  the rule's domain group.
     */
    auto addRoute(string method, string path, HandleFunction handle, string group = DEFAULT_ROUTE_GROUP)
    {
       logDebug(__FUNCTION__,method, path, handle, group);
        this._dispatcher.router.addRoute(method, path, handle, group);

        return this;
    }

	Application GET(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("GET", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}
	Application POST(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("POST", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}
	Application DELETE(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("DELETE", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}
	Application PATCH(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("PATCH", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}
	Application PUT(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("PUT", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}
	Application HEAD(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("HEAD", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}
	Application OPTIONS(string path,HandleFunction handle)
	{
        this._dispatcher.router.addRoute("OPTIONS", path, handle,DEFAULT_ROUTE_GROUP);
		return this;
	}

    // enable i18n
    Application enableLocale(string resPath = DEFAULT_LANGUAGE_PATH, string defaultLocale = "en-us")
    {
        I18n i18n = I18n.instance();

        i18n.loadLangResources(resPath);
        i18n.defaultLocale = defaultLocale;

        return this;
    }

    void setWebSocketFactory(WebSocketFactory webfactory)
    {
        _wfactory = webfactory;
    }

    version(NO_TASKPOOL){} else {
        @property TaskPool taskPool(){return _tpool;}
    }

    /// get the router.
    @property router()
    {
        return this._dispatcher.router();
    }

    @property server(){return _server;}

    @property mainLoop(){return _server.eventLoop;}

    @property loopGroup(){return _server.group;}

    @property AppConfig appConfig(){return Config.app;}

    void setCreateBuffer(CreatorBuffer cbuffer)
    {
        if(cbuffer)
            _cbuffer = cbuffer;
    }

    /*void setRedis(AppConfig.RedisConf conf)
    {
        version(USE_REDIS){
            if(conf.enabled == true && conf.host && conf.port)
            {
                conRedis.setDefaultHost(conf.host,conf.port,conf.password);    
            }
        }
    }

    void setMemcache(AppConfig.MemcacheConf conf)
    {
        version(USE_MEMCACHE){
            if(conf.enabled == true){
               logDebug(conf);
                auto tmp1 = split(conf.servers,","); 
                auto tmp2 = split(tmp1[0],":"); 
                if(tmp2[0] && tmp2[1]){
                    conMemcache.setDefaultHost(tmp2[0],tmp2[1].to!ushort);
                }
            }
        }
    }*/

    private void initCache(AppConfig.CacheConf config)
    {
		_manger.createCache("default" , config.storage , config.args , config.enableL2);
	}
    
    private void initSessionStorage(AppConfig.SessionConf config)
    {
		_sessionStorage = new SessionStorage(UCache.CreateUCache(config.storage , config.args , false));
      
		_sessionStorage.setPrefix(config.prefix);
        _sessionStorage.setExpire(config.expire);
    }

	CacheManger getCacheManger()
	{
		return _manger;
	}
	
	SessionStorage getSessionStorage()
	{
		return _sessionStorage;
	}
	
	UCache getCache()
	{
		return  _manger.getCache("default");

	}

	AccessManager getAccessManager()
	{
		return _accessManager;
	}

    /**
      Start the HTTPServer server , and block current thread.
     */
     void run()
	{
		start();
	}

	/*
	void run(Address addr)
	{
		Config.app.http.address = addr.toAddrString;
		Config.app.http.port = addr.toPortString.to!ushort;
		setConfig(Config.app);
		start();
	}*/

	void setConfig(AppConfig config)
	{
		setLogConfig(config.log);
		upConfig(config);
		//setRedis(config.redis);
		//setMemcache(config.memcache);
		initCache(config.cache);
		initSessionStorage(config.session);
	}

	void start()
	{
		writeln("Try to open http://",addr.toString(),"/");
		_server.start();
	}

    /**
      Stop the server.
     */
    void stop()
    {
        _server.stop();
    }
    private:
    RequestHandler newHandler(RequestHandler, HTTPMessage msg){
        if(!msg.upgraded)
        {
            return new Request(_cbuffer,&handleRequest,_maxBodySize);
        }
        else if(_wfactory)
        {
            return _wfactory.newWebSocket(msg);
        }

        return null;
    }

    Buffer defaultBuffer(HTTPMessage msg) nothrow
    {
        try{
            import std.experimental.allocator.gc_allocator;
            import kiss.container.ByteBuffer;
            if(msg.chunked == false)
            {
                string contign = msg.getHeaders.getSingleOrEmpty(HTTPHeaderCode.CONTENT_LENGTH);
                if(contign.length > 0)
                {
                    import std.conv;
                    uint len = 0;
                    collectException(to!(uint)(contign),len);
                    if(len > _maxBodySize)
                        return null;
                }
            }

            return new ByteBuffer!(GCAllocator)();
        }
        catch(Exception e)
        {
            showException(e);
            return null;
        }
    }

    void handleRequest(Request req) nothrow
    {
        this._dispatcher.dispatch(req);
    }

    private:
    void upConfig(AppConfig conf)
    {
        _maxBodySize = conf.upload.maxSize;
        version(NO_TASKPOOL)
        {
            // NOTHING
        }
        else
        {
            _tpool = new TaskPool(conf.http.workerThreads);
            _tpool.isDaemon = true;
        }

        HTTPServerOptions option = new HTTPServerOptions();
        option.maxHeaderSize = conf.http.maxHeaderSize;
        //option.listenBacklog = conf.http.listenBacklog;

        version(NO_TASKPOOL)
        {
            option.threads = conf.http.ioThreads + conf.http.workerThreads;
        }
        else
        {
            option.threads = conf.http.ioThreads;
        }

        option.timeOut = conf.http.keepAliveTimeOut;
        option.handlerFactories ~= (&newHandler);
        _server = new HttpServer(option);
        logDebug("addr:",conf.http.address, ":", conf.http.port);
        addr = parseAddress(conf.http.address,conf.http.port);
        HTTPServerOptions.IPConfig ipconf;
        ipconf.address = addr;

        _server.addBind(ipconf);

        //if(conf.webSocketFactory)
        //    _wfactory = conf.webSocketFactory;

       logDebug(conf.route.groups);

        version(NO_TASKPOOL)
        {
        }
        else
        {
            this._dispatcher.setWorkers(_tpool);
        }
        // init dispatcer and routes
        if (conf.route.groups)
        {
            import std.array : split;
            import std.string : strip;

            string[] groupConfig;

            foreach (v; split(conf.route.groups, ','))
            {
                groupConfig = split(v, ":");

                if (groupConfig.length == 3 || groupConfig.length == 4)
                {
                    string value = groupConfig[2];

                    if (groupConfig.length == 4)
                    {
                        if (std.conv.to!int(groupConfig[3]) > 0)
                        {
                            value ~= ":"~groupConfig[3];
                        }
                    }

                    this._dispatcher.addRouteGroup(strip(groupConfig[0]), strip(groupConfig[1]), strip(value));

                    continue;
                }

                logWarningf("Group config format error ( %s ).", v);
            }
        }

        this._dispatcher.loadRouteGroups();
    }

    void setLogConfig(ref AppConfig.LogConfig conf)
    {
		int level = 0;
        switch(conf.level)
        {
            case "all":
			case "trace":
			case "debug":
				level = 0;
                break;
            case "critical":
            case "error":
				level = 3;
                break;
            case "fatal":
				level = 4;
                break;
            case "info":
				level = 1;
                break;
            case "warning":
				level = 2;
                break;
            case "off":
				level = 5;
                break;
			default:
				level = 0;
        }
		LogConf logconf;
		logconf.level = cast(LogLevel)level;
		logconf.disableConsole = conf.disableConsole;
        if(!conf.file.empty)
		    logconf.fileName = buildPath(conf.path, conf.file);
		logconf.maxSize = conf.maxSize;
		logconf.maxNum = conf.maxNum;

		logLoadConf(logconf);

    }




    version(USE_KISS_RPC) {
        import kissrpc.RpcManager;
        public void startRpcService(T,A...)() {
            if (Config.app.rpc.enabled == false)
                return;
            string ip = Config.app.rpc.service.address;
            ushort port = Config.app.rpc.service.port;
            int threadNum = Config.app.rpc.service.workerThreads;
            RpcManager.getInstance().startService!(T,A)(ip, port, threadNum);
        }
        public void startRpcClient(T)(string ip, ushort port, int threadNum = 1) {
            if (Config.app.rpc.enabled == false)
                return;
            RpcManager.getInstance().connectService!(T)(ip, port, threadNum);
        }
    }

    this()
    {
        _cbuffer = &defaultBuffer;
		_accessManager = new AccessManager();
		_manger = new CacheManger();

        this._dispatcher = new Dispatcher();
		setConfig(Config.app);
    }

    __gshared static Application _app;

    private:
    Address addr;
    HttpServer _server;
    WebSocketFactory _wfactory;
    uint _maxBodySize;
    CreatorBuffer _cbuffer;
    Dispatcher _dispatcher;
    CacheManger _manger;
	SessionStorage _sessionStorage;
	AccessManager  _accessManager;

    version(NO_TASKPOOL)
    {
        // NOTHING TODO
    }
    else
    {
        __gshared TaskPool _tpool;
    }
}
