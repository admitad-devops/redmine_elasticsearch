module Elasticsearch
  module Model
    class Multimodel
      # Get an Array of document types used for retrieving documents when doing a search across multiple models
      # NOTE: Workaround for one index and multiple types for Elasticsearch 7.x
      # @return [Array] the list of document types used for retrieving documents
      def document_type
        index_name.uniq.size > 1 ? models.map { |m| m.document_type } : []
      end
    end
  end
end
