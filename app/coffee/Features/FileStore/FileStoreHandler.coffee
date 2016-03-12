logger = require("logger-sharelatex")
fs = require("fs")
request = require("request")
settings = require("settings-sharelatex")

oneMinInMs = 60 * 1000
fiveMinsInMs = oneMinInMs * 5

module.exports = FileStoreHandler =

	uploadFileFromDisk: (project_id, file_id, fsPath, callback)->
		fs.lstat fsPath, (err, stat)->
			if err?
				logger.err err:err, "error with path symlink check"
				return callback(err)
			if stat.isSymbolicLink()
				logger.log project_id:project_id, file_id:file_id, fsPath:fsPath, "error uploading file from disk, file path is symlink"
				return callback('file is from symlink')
			logger.log project_id:project_id, file_id:file_id, fsPath:fsPath, "uploading file from disk"
			readStream = fs.createReadStream(fsPath)
			FileStoreHandler.putFileStream project_id, file_id, readStream, callback

	putFileStream: (project_id, file_id, readStream, callback)->
		logger.log project_id:project_id, file_id:file_id, "putting stream"
		opts =
			method: "post"
			uri: @_buildUrl(project_id, file_id)
			timeout:fiveMinsInMs
		writeStream = request(opts)
		# FIXME: potential double callbacks
		writeStream.on "end", callback
		readStream.on "error", (err)->
			logger.err err:err, project_id:project_id, file_id:file_id, "something went wrong on the read stream of putFileStream"
			callback err
		writeStream.on "error", (err)->
			logger.err err:err, project_id:project_id, file_id:file_id, "something went wrong on the write stream of putFileStream"
			callback err
		readStream.pipe writeStream

	getFileStream: (project_id, file_id, query, callback)->
		logger.log project_id:project_id, file_id:file_id, query:query, "getting file stream from file store"
		queryString = ""
		if query? and query["format"]?
			queryString = "?format=#{query['format']}"
		opts =
			method : "get"
			uri: "#{@_buildUrl(project_id, file_id)}#{queryString}"
			timeout:fiveMinsInMs
		readStream = request(opts)
		callback(null, readStream)

	deleteFile: (project_id, file_id, callback)->
		logger.log project_id:project_id, file_id:file_id, "telling file store to delete file"
		opts =
			method : "delete"
			uri: @_buildUrl(project_id, file_id)
			timeout:fiveMinsInMs
		request opts, (err, response)->
			if err?
				logger.err err:err, project_id:project_id, file_id:file_id, "something went wrong deleting file from filestore"
			callback(err)

	copyFile: (oldProject_id, oldFile_id, newProject_id, newFile_id, callback)->
		logger.log oldProject_id:oldProject_id, oldFile_id:oldFile_id, newProject_id:newProject_id, newFile_id:newFile_id, "telling filestore to copy a file"
		opts =
			method : "put"
			json:
				source:
					project_id:oldProject_id
					file_id:oldFile_id
			uri: @_buildUrl(newProject_id, newFile_id)
			timeout:fiveMinsInMs
		request opts, (err)->
			if err?
				logger.err err:err, oldProject_id:oldProject_id, oldFile_id:oldFile_id, newProject_id:newProject_id, newFile_id:newFile_id, "something went wrong telling filestore api to copy file"
			callback(err)

	_buildUrl: (project_id, file_id)->
		return "#{settings.apis.filestore.url}/project/#{project_id}/file/#{file_id}"
