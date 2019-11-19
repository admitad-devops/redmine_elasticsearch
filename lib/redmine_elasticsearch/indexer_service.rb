module RedmineElasticsearch

  class IndexerError < StandardError
  end

  class IndexerService

    class << self
      def recreate_index
        delete_index if index_exists?
        create_index
        RedmineElasticsearch.refresh_indices
      end

      # Recreate index and mapping and then import documents
      # @return [Integer] errors count
      #
      def reindex_all(options = {}, &block)

        # Errors counter
        errors = 0

        # Delete and create indexes
        recreate_index

        # Importing parent project first
        ParentProject.import

        # Import records from all searchable classes
        RedmineElasticsearch.search_klasses.each do |search_klass|
          errors += search_klass.import options, &block
        end

        # Refresh index for allowing searching right after reindex
        RedmineElasticsearch.client.indices.refresh

        errors
      end

      # Reindex only given search type
      def reindex(search_type, options = {}, &block)
        search_klass = find_search_klass(search_type)
        search_type = search_type.singularize
        create_index unless index_exists?

        options[:type] = '_doc'
        options[:transform] = lambda {|model|
          data = model.to_indexed_json
          data[:type] = search_type
          parent = data.delete(:_parent)
          data[:parent_project] = {name: search_type, parent: "parent_project-#{parent}"}
          { index: {
              _id: "#{search_type}-#{model.id}",
              routing: parent,
              data: data
          }}
        }

        # Import records from given searchable class
        errors = search_klass.import options do |imported_records|
          yield(imported_records) if block_given?
        end

        errors
      end

      def count_estimated_records(search_type = nil)
        search_klass = search_type && find_search_klass(search_type)
        search_klass ?
          search_klass.searching_scope.count :
          RedmineElasticsearch.search_klasses.inject(0) { |sum, klass| sum + klass.searching_scope.count }
      end

      protected

      def logger
        ActiveRecord::Base.logger
      end

      def index_exists?
        RedmineElasticsearch.client.indices.exists? index: RedmineElasticsearch::INDEX_NAME
      end

      def create_index
        RedmineElasticsearch.client.indices.create(
          index: RedmineElasticsearch::INDEX_NAME,
          body:  {
            settings: {
              index:    {
                number_of_shards:   1,
                number_of_replicas: 0,
                max_ngram_diff: 6,
              },
              analysis: {
                analyzer: {
                  default:        {
                    type:      'custom',
                    tokenizer: 'standard',
                    char_filter: %w(html_strip ru_mapping),
                    filter: %w(lowercase custom_word_delimiter en_stopwords ru_stopwords ru_RU en_US)
                  },
                },
                char_filter: {
                    ru_mapping: {
                        type: 'mapping',
                        mappings: %w(Ё=>Е ё=>е)
                    }
                },
                tokenizer: {
                    ru_nGram: {
                        type: 'nGram',
                        min_gram: 4,
                        max_gram: 10
                    }
                },
                filter: {
                    ru_stopwords: {
                        type: 'stop',
                        stopwords: 'а,без,более,бы,был,была,были,было,быть,в,вам,вас,весь,во,вот,все,всего,всех,вы,где,да,даже,для,до,его,ее,если,есть,еще,же,за,здесь,и,из,или,им,их,к,как,ко,когда,кто,ли,либо,мне,может,мы,на,надо,наш,не,него,нее,нет,ни,них,но,ну,о,об,однако,он,она,они,оно,от,очень,по,под,при,с,со,так,также,такой,там,те,тем,то,того,тоже,той,только,том,ты,у,уже,хотя,чего,чей,чем,что,чтобы,чье,чья,эта,эти,это'
                    },
                    en_stopwords: {
                        type: 'stop',
                        stopwords: 'a,an,and,are,as,at,be,but,by,for,if,in,into,is,it,no,not,of,on,or,such,that,the,their,then,there,these,they,this,to,was,will,with'
                    },
                    my_nGram: {
                        type: 'nGram',
                        min_gram: 2,
                        max_gram: 8
                    },
                    custom_word_delimiter: {
                        type: 'word_delimiter',
                        generate_word_parts: true,
                        generate_number_parts: true,
                        catenate_words: true,
                        catenate_numbers: false,
                        catenate_all: true,
                        split_on_case_change: true,
                        preserve_original: true,
                        split_on_numerics: false
                    },
                    ru_RU: {
                        type: 'hunspell',
                        locale: 'ru_RU',
                        dedup: true
                    },
                    en_US: {
                        type: 'hunspell',
                        locale: 'en_US',
                        dedup: true
                    }
                },
              }
            },
            mappings: {
              properties: {
                  type:           {type: 'keyword'},
                  title:          {type: 'text', analyzer: 'default'},
                  description:    {type: 'text', analyzer: 'default'},
                  datetime:       {type: 'date'},
                  url:            {type: 'text', index: false},
                  fixed_version:  {type: 'keyword'},
                  parent_project: {type: 'join', relations: {parent_project: Redmine::Search.available_search_types.map(&:singularize)}},
              }
            }
          }
        )
      end

      def delete_index
        RedmineElasticsearch.client.indices.delete index: RedmineElasticsearch::INDEX_NAME
      end

      def find_search_klass(search_type)
        validate_search_type(search_type)
        RedmineElasticsearch.type2class(search_type)
      end

      def validate_search_type(search_type)
        unless Redmine::Search.available_search_types.include?(search_type)
          raise IndexError.new("Wrong search type [#{search_type}]. Available search types are #{Redmine::Search.available_search_types}")
        end
      end
    end
  end
end
