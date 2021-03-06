# This library is now obsolete due to the [Gradle Android plugin 1.4.0](http://android-developers.blogspot.com/2015/09/android-studio-14.html), which will manage and automatically render your vector drawables for you.

# svg-to-android

This is a cli tool that renders SVGs into appropriately sized Android drawable PNGs for different densities.

## Installation

To install from npm, run

`npm install -g svg-to-android`

## Usage

### CLI

`svg-to-android input... [-q] [-o outputDir] [-d density]`

 - `input...`: a list of SVG files
 - `-q`: Makes the tool quiet; will not output to console
 - `-o outputDir`: Specify where to save the drawable-{density} folders. Defaults to current directory.
 - `-d density`: Specify what density the SVG is currently sized as. That is, the dimensions defined in the SVG will be considered to be the density you provide, and all other densities will be resized relative to that density. Defaults to mdpi.
 - `-D outputDensity`: Specify which densities you want to render into. Use this option multiple times for multiple output densities. Defaults to all dpis from ldpi to xxxdpi.

### Module

svg-to-android can also be used in your own Node scripts. Here is an example:

```javascript
var svg2android = new Svg2Android({
  outputDir: "path/to/output",
  density: 'mdpi',
  verbose: false
});

// renderSvg accepts a single path or an array of paths
svg2android.renderSvg(["dog.svg", "cat.svg"]);
```


## Building

To compile the source just run `grunt`.
