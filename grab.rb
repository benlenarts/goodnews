require 'rss'
require 'json'
require 'bundler/inline'

gemfile do 
  source 'https://rubygems.org'
  gem 'dotenv'
  gem 'ruby-openai'
  gem 'pry'
  gem 'builder'
end
#%w{pry pp json csv date time}.map{|r|require r};puts "\n=start\n\n";at_exit {puts "\n=finish"}

require 'dotenv/load'

# MAKE SURE THESE ARE SAFE TO `curl "#{url}"` BECAUSE THAT'S WHAT HAPPENS WITH THEM!
RSS_URLS = [
  "https://phys.org/rss-feed/",
  "https://medicalxpress.com/rss-feed/",
  "https://techxplore.com/rss-feed/"
]

DB_PATH = "db.json"
DB = JSON.parse(File.read(DB_PATH)) if File.exist?(DB_PATH)
DB ||= { "openai_cache" => {}}

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_ACCESS_KEY")
end

def cached_chat str
  DB["openai_cache"][str] ||= chat(str)
end

def chat str
  #puts "$"
  sleep 0.5
  result = OpenAI::Client.new.chat(
    parameters: {
        model: "gpt-3.5-turbo", 
        messages: [{ role: "user", content: str}],
    }
  ).dig("choices", 0, "message", "content")
end

def is_positive_news?(article)
  prompt = "Is the following start of an article likely to be positive news? Please answer only yes or no.\n\n#{article.title}\n\n#{article.description}"
  
  result = cached_chat(prompt)
  result.downcase.gsub(/[^a-z]/,"") == "yes"
end

# Function to generate HTML
def generate_html(positive_articles)
  File.open("positive_news.html", "w") do |file|
    xml = Builder::XmlMarkup.new(target: file, indent: 2)

    xml.html do
      xml.head do
        xml.link('rel' => 'stylesheet', 'type' => 'text/css', 'href' => 'pico.classless.min.css')
        xml.link('rel' => 'stylesheet', 'type' => 'text/css', 'href' => 'style.css')
        xml.title "Good news"
      end
      xml.body do
        xml.header("style" => "padding-bottom: 0px;") do
          xml.h1 "Good news, everyone!"
          xml.img('src' => 'farnsworth.jpeg')
        end

        xml.main("class" => "container") do 
          positive_articles.sort_by(&:date).each do |article|
            xml.article do
              xml.header do
                xml.a(article.title, 'href' => article.link)
                xml.text! "(#{URI(article.link).host})"
              end
              xml.p article.description
              xml.footer do 
                xml.small article.date
              end
            end
          end
        end
        xml.footer do
          xml.p "Generated by a small script that scrapes a bunch of RSS feeds, and for each item asks chatgpt if it looks like a positive news item. For when you need a bit of hope after a particularly depressing news day. Currently scrapes the following feeds, but I'm happy to add more (contact info on www.luitjes.it):"
          xml.ul do
            RSS_URLS.each do |url|
              xml.li url
            end
          end
        end
      end
    end
  end
  `mv positive_news.html /var/www/goodnews.luitjes.it/html/index.html`
end


positive_articles = []

RSS_URLS.each do |url|
  raw = `curl -s "#{url}"`
  feed = RSS::Parser.parse(raw)
  feed.items.each do |item|
    positive_articles << item if is_positive_news?(item)
  end
end

generate_html(positive_articles)
#puts "HTML page generated with positive news articles."
File.open(DB_PATH, 'w') {|f| f.write DB.to_json}

