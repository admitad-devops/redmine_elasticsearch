module ApplicationSearch
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Model

    index_name RedmineElasticsearch::INDEX_NAME
    document_type RedmineElasticsearch::klass2type(self).singularize

    after_commit :async_update_index
  end

  def to_indexed_json
    RedmineElasticsearch::SerializerService.serialize_to_json(self)
  end

  def async_update_index
    Workers::Indexer.defer(self)
  end

  module ClassMethods

    def additional_index_mappings
      return {} unless Rails.configuration.respond_to?(:additional_index_properties)
      Rails.configuration.additional_index_properties[self.name.tableize.to_sym] || {}
    end

    def allowed_to_search_query(user, options = {})
      options = options.merge(
        permission: :view_project,
        type:       document_type
      )
      ParentProject.allowed_to_search_query(user, options)
    end

    def searching_scope
      all
    end

    def remove_from_index(id)
      __elasticsearch__.client.delete index: index_name, type: document_type, id: id, routing: id
    end
  end

  def update_index
    relation = self.class.searching_scope.where(id: id)

    if relation.size.zero?
      begin
        self.class.remove_from_index(id)
        return
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        return
      end
    end

    options = {}
    options[:type] = '_doc'
    options[:transform] = lambda {|model|
      data = model.to_indexed_json
      data[:type] = RedmineElasticsearch.klass2type(model.class).singularize
      parent = data.delete(:_parent)
      data[:parent_project] = {name: data[:type], parent: "parent_project-#{parent}"}
      { index: {
          _id: "#{data[:type]}-#{model.id}",
          routing: parent,
          data: data
      }}
    }

    relation.import options
  end
end
