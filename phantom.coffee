dnode    = require 'dnode'
http     = require 'http'
shoe     = require 'shoe'
child    = require 'child_process'

# the list of phantomjs RPC wrapper
phanta = []

# @Description: starts and returns a child process running phantomjs
# @param: port:int
# @args: args:object
# @return: ps:object
startPhantomProcess = (binary, port, args) ->
  ps = child.spawn binary, args.concat [__dirname+'/shim.js', port]

  ps.stdout.on 'data', (data) -> console.log "phantom stdout: #{data}"

  ps.stderr.on 'data', (data) ->
    return if data.toString('utf8').match /No such method.*socketSentData/ #Stupid, stupid QTWebKit
    console.warn "phantom stderr: #{data}"

#  ps.on 'exit', (code, signal) ->
#    if signal
#      throw new Error("signal killed phantomjs: #{signal}")
#    throw new Error("abnormal phantomjs exit code: #{code}")
#    console.assert not signal?, "signal killed phantomjs: #{signal}"
#    console.assert code is 0, "abnormal phantomjs exit code: #{code}"

  ps

# @Description: kills off all phantom processes within spawned by this parent process when it is exits
process.on 'exit', ->
  phantom.exit() for phantom in phanta


# @Description: We need this because dnode does magic clever stuff with functions, but we want the function to make it intact to phantom
wrap = (ph) ->
  ph._createPage = ph.createPage
  ph.createPage = (cb) ->
    ph._createPage (page) ->
      page._evaluate = page.evaluate
      page.evaluate = (fn, cb, args...) -> page._evaluate.apply(page, [fn.toString(), cb].concat(args))
      cb page



module.exports =
  create: ->
    args = []
    options = {}
    for arg in arguments
      switch typeof arg
        when 'function' then cb = arg
        when 'string' then args.push arg
        when 'object' then options = arg
    options.binary ?= 'phantomjs'
    options.port ?= 12300

    phantom = null

    httpServer = http.createServer()
    httpServer.listen options.port

    httpServer.on 'listening', () ->

      ps = startPhantomProcess options.binary, options.port, args

      # @Description: when the background phantomjs child process exits or crashes
      #   removes the current dNode phantomjs RPC wrapper from the list of phantomjs RPC wrapper
      ps.on 'exit', (code) ->
        httpServer.close()

        # in case phantomjs exited with abnormal exit code, call the hooked fn if it exists
        if code != 0
          if options.onCriticalExit
            return options.onCriticalExit(code)
          else
            throw new Error("abnormal phantomjs exit code: #{code}")

        if phantom
          phantom && phantom.onExit && phantom.onExit() # calls the onExit method if it exist
          phanta = (p for p in phanta when p isnt phantom)

    sock = shoe (stream) ->

      d = dnode()

      d.on 'remote', (phantom) ->
        wrap phantom
        phanta.push phantom
        cb? phantom

      d.pipe stream
      stream.pipe d

    sock.install httpServer, '/dnode'
