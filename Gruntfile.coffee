module.exports = (grunt) ->

    grunt.task.loadNpmTasks 'grunt-contrib-coffee'

    grunt.initConfig
        pkg:
            grunt.file.readJSON('package.json')

        coffee:
            compile:
                expand: true
                flatten: true
                cwd: "src/"
                src: ['**/*.coffee']
                dest: 'lib/'
                ext: '.js'


    grunt.registerTask 'build', ['coffee']
    grunt.registerTask 'default', ['build']
