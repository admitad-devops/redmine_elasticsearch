require 'redmine'

Redmine::Plugin.register :redmine_elasticsearch do
  name        'Redmine Elasticsearch Plugin'
  description 'This plugin integrates the Elasticsearch full-text search engine into Redmine. Forked from https://github.com/Restream/redmine_elasticsearch'
  author      'Boris Gorbylev'
  author_url  'https://github.com/ekho'
  version     '1.0.1'
  url         'https://github.com/admitad-devops/redmine_elasticsearch'

  requires_redmine version_or_higher: '2.1'
end

require 'redmine_elasticsearch'
