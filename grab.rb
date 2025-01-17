require 'rss'
require 'json'
require 'time'
require 'bundler/inline'

gemfile do 
  source 'https://rubygems.org'
  gem 'dotenv'
  gem 'ruby-openai'
  gem 'pry'
  gem 'builder'
  gem 'tzinfo'
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
  prompt = "Is the following news item likely to make people feel hopeful? Please answer only yes or no.\n\n#{article.title}\n\n#{article.description}"
  
  result = cached_chat(prompt)
  result.downcase.gsub(/[^a-z]/,"") == "yes"
end

# Function to generate HTML
def generate_html(positive_articles)
  xml = Builder::XmlMarkup.new(indent: 2)

  xml.html do
    xml.head do
      xml.link('rel' => 'alternate', 'type' => 'application/rss+xml', 'href' => 'rss.xml', 'title' => 'RSS feed')
      xml.link('rel' => 'stylesheet', 'type' => 'text/css', 'href' => 'pico.classless.min.css')
      xml.link('rel' => 'stylesheet', 'type' => 'text/css', 'href' => 'style.css')
      xml.title "Good news"
    end
    xml.body do
      xml.header do
        xml.h1 "Good news, everyone!"
        xml.img('src' => 'farnsworth.jpeg')
        xml.small do 
          xml.text! "Inject a bit of hope in your news diet. AI-curated and not manually reviewed, so the occasional mistake may pop up. See "
          xml.a("below", "href" => "#about") 
          xml.text! " for more information."
        end
      end

      xml.main("class" => "container") do 
        positive_articles.sort_by(&:date).reverse.each do |article|
          xml.article do
            xml.header do
              xml.a(article.title, 'href' => article.link)
              xml.text! "(#{URI(article.link).host})"
            end
            xml.p article.description
            xml.footer do 
              local = TZInfo::Timezone.get('Europe/Amsterdam').to_local(article.date).to_s
              xml.small local
            end
          end
        end
      end
      xml.footer("id" => "about") do
        xml.h3 "About"
        xml.p do 
          xml.text! "Generated by a small script that scrapes a bunch of RSS feeds every hour, and for each item asks chatgpt if it's likely to make people feel hopeful. Currently scrapes the following feeds, but I'm happy to add more (contact info on"
          xml.a "www.luitjes.it", "href" => "https://www.luitjes.it"
          xml.text! " or "
          xml.a "create an issue", "href" => "https://github.com/lucasluitjes/goodnews/issues/new"
          xml.text! "on github):"
        end
        xml.ul do
          RSS_URLS.each do |url|
            xml.li url
          end
        end
        xml.p do
          xml.text! "Source available on "
          xml.a "github.", "href" => "https://github.com/lucasluitjes/goodnews"
        end
      end
    end
  end
end

def generate_rss(positive_articles)
  xml = Builder::XmlMarkup.new(indent: 2)

  xml.rss("version" => "2.0") do
    xml.channel do
      xml.title "Good news"
      xml.description "Inject a bit of hope in your news diet. AI-curated and not manually reviewed, so the occasional mistake may pop up."
      xml.link "https://goodnews.luitjes.it"
      xml.language "en-us"
      positive_articles.sort_by(&:date).reverse.each do |article|
        xml.item do
          xml.title article.title
          xml.description article.description
          xml.pubDate article.date.to_s
          xml.link article.link
          xml.guid article.link
        end
      end
    end
  end
end

positive_articles = []

RSS_URLS.each do |url|
  raw = `curl -s "#{url}"`
  feed = RSS::Parser.parse(raw)
  feed.items.each do |item|
    positive_articles << item if is_positive_news?(item)
  end
end

result_dir = "/var/www/goodnews.luitjes.it/html"
IO.write(File.join(result_dir, "rss.xml"), generate_rss(positive_articles))
IO.write(File.join(result_dir, "index.html"), generate_html(positive_articles))
#puts "HTML page generated with positive news articles."
File.open(DB_PATH, 'w') {|f| f.write DB.to_json}

