module Paperclip
  module Storage
    # MongoDB's GridFS storage system (http://www.mongodb.org/display/DOCS/GridFS) uses
    # a chunking strategy to store files in a mongodb database.
    # Specific options for GridFS:
    # * +gridfs_credentials+: Similar to +s3_credentials+, this can be a path, a File, or
    #   a Hash. Keys are as follows:
    #   * +database+: the name of the MongoDB database to connect to. This can also be
    #     a +Mongo::DB+ object, in which case that connection will be used, and other
    #     credentials will be ignored.
    #   * +host+: defaults to +localhost+
    #   * +username+ and +password+: optional authentication for the database server.
    #
    # Note that, because files stored using the +:gridfs+ storage module are stored
    # within the database rather than the file system, you'll need to work out a method
    # to extract the file data to serve it over HTTP. This is pretty trivial using
    # Rails Metal.

    module Gridfs
      def self.extended base
        begin
          require 'mongo'
        rescue LoadError => e
          e.message << " (You may need to install the mongo gem)"
          raise e
        end
      
        base.instance_eval do
          @gridfs_connection = get_database_connection(parse_credentials(@options[:gridfs]))
          @gridfs            = Mongo::GridFileSystem.new(@gridfs_connection)
        end
      end

      def parse_credentials creds
        creds = find_credentials(creds).stringify_keys
        env = Object.const_defined?(:Rails) ? Rails.env : nil
        (creds[env] || creds).symbolize_keys
      end
      
      def exists? style = default_style
        if original_filename
          !!@gridfs.exist?(:filename => path(style))
        else
          false
        end
      end
      
      # Returns a binary representation of the data of the file assigned to the given style
      def to_file style = default_style
        @queued_for_write[style] || (@gridfs.open(path(style), 'r') if exists?(style))
      end

      def flush_writes #:nodoc:
        @queued_for_write.each do |style, file|
          log("saving #{path(style)}")
          @gridfs.open(path(style), 'w', :content_type => content_type) do |f|
            f.write file.read
          end
        end
        after_flush_writes # allows attachment to clean up temp files
        @queued_for_write = {}
      end

      def flush_deletes #:nodoc:
        @queued_for_delete.each do |path|
          log("deleting #{path}")
          @gridfs.delete(path)
        end
        @queued_for_delete = []
      end

      private
      
      def get_database_connection creds
        return creds[:database] if creds[:database].is_a? Mongo::DB
        db = Mongo::MongoClient.new(creds[:host], creds[:port]).db(creds[:database])
        db.authenticate(creds[:username], creds[:password]) if creds[:username] && creds[:password]
        return db
      end

      def find_credentials creds
        case creds
        when File
          YAML::load(ERB.new(File.read(creds.path)).result)
        when String, Pathname
          YAML::load(ERB.new(File.read(creds)).result)
        when Hash
          creds
        else
          raise ArgumentError, "Credentials are not a path, file or hash."
        end
      end
    end
  end
end
