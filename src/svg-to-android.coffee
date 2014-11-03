fs = require 'fs'
path = require 'path'
Q = require 'q'
phantomPath = require('phantomjs').path
phantom = require 'phantom'
argv = (require 'yargs')
	.alias 'o', 'output'
	.alias 'd', 'density'
	.alias 'q', 'quiet'
	.argv

class Svg2Android
	constructor: (opts) ->
		{@outputDir, @verbose} = opts

		# Base multiplier to figure out how to size everything
		# Default is to assume mdpi
		@baseMultiplier = @densityToMultiplier(opts.density) or 1

		@densities = ['ldpi', 'mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']

	_log: (msg) -> console.log msg if @verbose

	densityToMultiplier: (density) ->
		switch density.toLowerCase()
			when 'ldpi' or 'l' then 0.75
			when 'mdpi' or 'm' then 1
			when 'hdpi' or 'h' then 1.5
			when 'xhdpi' or 'x' then 2
			when 'xxhdpi' or 'xx' then 3
			when 'xxxhdpi' or 'xxx' then 4

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
		phantom.create (ph) =>
			svgPromises = []
			for svg, i in svgs
				@_log "Rendering #{input[i]}"
				svgPromises.push @_renderAllDensities ph, svg, input[i]
			Q.all svgPromises
			.then ->
				ph.exit();

		, path: path.dirname(phantomPath)+'/'

	# Renders a single SVG into all densities
	# Returns a promise when done rendering all densities
	_renderAllDensities: (ph, content, inputPath) ->
		deferred = Q.defer()
		densityPromises = []
		for density in @densities
			densityPromises.push @_renderDensity ph, content, inputPath, density
		Q.all densityPromises
		.then deferred.resolve
		return deferred.promise

	# Renders a single SVG at a single density
	# Returns a promise when done rendering that density
	_renderDensity: (ph, content, inputPath, density) ->
		deferred = Q.defer()
		ph.createPage (page) =>
			page.set 'onConsoleMessage', (msg) =>
				console.log msg
			page.set 'onError', (msg, stack) =>
				console.error msg
				console.error stack
			page.set 'onLoadFinished',  =>
				multiplier = @densityToMultiplier(density) / @baseMultiplier
				@_setSvgDimensions page, multiplier
				.then =>
					outputDir = path.join @outputDir, "drawable-#{density}", path.basename(inputPath, '.svg')+'.png'
					page.render outputDir, {format: 'png', quality: 100}, =>
						@_log "\tRendered drawable-#{density} at #{outputDir}"
						deferred.resolve()
			page.set 'content', content
		return deferred.promise

	# Figures out the width of the SVG and resizes by a multiplier
	# Also sets up the viewport and clip rect
	# Based on the same method from https://github.com/metabench/jsgui-node-render-svg/blob/master/jsgui-node-render-svg.js
	# Returns a promise that resolves with the dimensions object
	_setSvgDimensions: (page, multiplier) ->
		deferred = Q.defer();
		page.evaluate (multiplier) ->
			svg = document.getElementsByTagName('svg')[0]
			bbox = svg.getBoundingClientRect()
			width = svg.getAttribute('width');
			height = svg.getAttribute('height');
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

			if not width
				width = bbox.width
			if not height
				height = bbox.height

			svg.setAttribute 'viewBox', "0 0 #{width} #{height}"

			width *= multiplier
			height *= multiplier
			svg.setAttribute 'width', width
			svg.setAttribute 'height', height

			return {width, height, usesViewBox}
		, (dimensions) ->
			page.set 'viewportSize',
				width: dimensions.width
				height: dimensions.height
			, =>
				page.set 'clipRect',
					top: 8
					left: 8
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
	svg2android = new Svg2Android
		outputDir: argv.output or './'
		density: argv.density or 'mdpi'
		verbose: !argv.quiet
	svg2android.renderSvg argv._
