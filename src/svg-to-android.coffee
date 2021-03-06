fs = require 'fs'
path = require 'path'
Q = require 'q'
phantomPath = require('phantomjs').path
phantom = require 'phantom'
argv = (require 'yargs')
	.alias 'o', 'output'
	.alias 'd', 'density'
	.alias 'q', 'quiet'
	.alias 'D', 'output-density'
	.default 'd', 'mdpi'
	.default 'D', 'mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi'
	.default 'o', './'
	.demand 1
	.usage 'Render SVGs into all android density PNGs.\nUsage: $0 [-v] [-d inputDensity] [-D outputDensity] [-o outputDir] svg1 [svg2...]'
	.example '$0 -o drawables/ big_dog.svg', 'Renders big_dog.svg into densities ldpi to xxxdpi in the drawables directory.'
	.describe 'd', 'The density of the input svgs.'
	.describe 'D', 'The output density to render as.'
	.describe 'o', 'The output directory to write rendered files into.'
	.describe 'q', 'Makes this tool run quietly.'
	.argv

class Svg2Android
	constructor: (opts) ->
		{@outputDir, @verbose, outputDensity: @densities} = opts

		# Base multiplier to figure out how to size everything
		# Default is to assume mdpi
		@baseMultiplier = @densityToMultiplier(opts.density) or 1

		@densities ?= ['ldpi', 'mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']

	_log: (msg) -> console.log msg if @verbose

	densityToMultiplier: (density) ->
		switch density.toLowerCase()
			when 'ldpi', 'l' then 0.75
			when 'mdpi', 'm' then 1
			when 'hdpi', 'h' then 1.5
			when 'xhdpi', 'x' then 2
			when 'xxhdpi', 'xx' then 3
			when 'xxxhdpi', 'xxx' then 4

	loadPhantom: ->
		Q.fcall =>
			if @ph? then @ph

			else
				deferred = Q.defer()

				phantom.create (ph) =>
					@ph = ph
					deferred.resolve ph

				, path: path.dirname(phantomPath)+'/'

				deferred.promise

	close: ->
		if @ph?
			@ph.exit()
			@ph = null

	# Renders given SVGs to output directory given in constructor
	# Assuming the file at current size is the given density
	# Argument can be a string path or array of paths
	# This starts up a PhantomJS process each time so it's best to provide all SVGs in an array
	renderSvg: (input) ->
		# Read SVGs from file
		if input not instanceof Array
			input = [input]
		svgs = (fs.readFileSync(i).toString() for i in input)

		# Render SVGs
		@loadPhantom()

		.then =>
			svgPromises = []
			for svg, i in svgs
				@_log "Rendering #{input[i]}"
				svgPromises.push @_renderAllDensities svg, input[i]

			Q.all svgPromises

		.then => @close()

	# Renders a single SVG into all densities
	# Returns a promise when done rendering all densities
	_renderAllDensities: (content, inputPath) ->
		densityPromises = []
		for density in @densities
			densityPromises.push @_renderDensity content, inputPath, density
		return Q.all densityPromises

	# Renders a single SVG at a single density
	# Returns a promise when done rendering that density
	_renderDensity: (content, inputPath, density) ->
		deferred = Q.defer()
		@ph.createPage (page) =>
			page.set 'onConsoleMessage', (msg) =>
				console.log msg
			page.set 'onError', (msg, stack) =>
				console.error msg
				console.error stack
			page.open inputPath,  =>
				multiplier = @densityToMultiplier(density) / @baseMultiplier
				@_setSvgDimensions page, multiplier

				.then =>

					outputDir = path.join @outputDir, "drawable-#{density}", path.basename(inputPath, '.svg')+'.png'
					page.render outputDir, {format: 'png', quality: 100}, =>
						@_log "\tRendered drawable-#{density} at #{outputDir}"
						deferred.resolve()
		return deferred.promise

	# Figures out the width of the SVG and resizes by a multiplier
	# Also sets up the viewport and clip rect
	# Based on the same method from https://github.com/metabench/jsgui-node-render-svg/blob/master/jsgui-node-render-svg.js
	# Returns a promise that resolves with the dimensions object
	_setSvgDimensions: (page, multiplier) ->
		deferred = Q.defer();
		page.evaluate (multiplier) ->
			svg = document.documentElement
			bbox = svg.getBoundingClientRect()
			width = parseInt svg.getAttribute 'width';
			height = parseInt svg.getAttribute 'height';
			viewBoxWidth = svg.viewBox and svg.viewBox.animVal and svg.viewBox.animVal.width;
			viewBoxHeight = svg.viewBox and svg.viewBox.animVal and svg.viewBox.animVal.height;
			usesViewBox = viewBoxWidth and viewBoxHeight

			if usesViewBox
				if width and not height
					height = width * viewBoxHeight / viewBoxWidth
				if height and not width
					width = height * viewBoxWidth / viewBoxHeight
				if not width and not height
					width = viewBoxWidth
					height = viewBoxHeight
			else
				viewBoxWidth = width
				viewBoxHeight = height

			if not width
				width = bbox.width
			if not height
				height = bbox.height

			width *= multiplier
			height *= multiplier
			svg.setAttribute 'width', width
			svg.setAttribute 'height', height
			svg.setAttribute 'viewBox', "0 0 #{viewBoxWidth} #{viewBoxHeight}"

			return {width, height, usesViewBox}
		, (dimensions) ->
			page.set 'viewportSize',
				width: dimensions.width
				height: dimensions.height
			, =>
				page.set 'clipRect',
					top: 0
					left: 0
					width: dimensions.width
					height: dimensions.height
				, =>
					deferred.resolve()
		, multiplier
		return deferred.promise

# Script is run as a command

# usage `svg-to-android input... [-q] [-o outputDir] [-d density]
module.exports = Svg2Android

if module.parent.isBinScript
	outputDensity = null
	if argv['output-density']? and argv['output-density'].length > 0
		outputDensity = []
		if argv['output-density'] instanceof Array
			argv['output-density'].forEach (i) -> outputDensity = outputDensity.concat i.split ','
		else
			outputDensity = outputDensity.concat argv['output-density'].split ','

	svg2android = new Svg2Android
		outputDir: argv.output or './'
		density: argv.density or 'mdpi'
		verbose: !argv.quiet
		outputDensity: outputDensity

	glob = require 'glob'
	async = require 'async'

	cache = {}
	matches = {}
	async.eachSeries argv._,
		(arg, done) ->
			glob arg, {cache}, (err, files) ->
				return done err if err?

				(matches[file] = true) for file in files
				done()

		, (err) ->
			return console.error err if err?

			files = Object.keys matches

			svg2android.renderSvg files
