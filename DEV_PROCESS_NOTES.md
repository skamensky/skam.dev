# SKam.dev Planning
🇸hmuel 🇰‎🇦‎🇲 ensky ([skam.dev](skam.dev))


* High level ideas for my website
	- It should be my resume and show my github activity
	- Display the media I consume. Including
		+ Listened to podcasts
		+ Watched movies/tv shows
		+ Books read
	- Host interactive demos of any work I do
	- Be my blog if I feel like writing anything
	- A quick to load front end. This gives us three options
		1. Be a MPA with modern JS components (apparently this is [called](https://stackoverflow.com/a/55833921/4188138) a microfrontend) interspersed between templated html
		2. Be a full SPA with server side rendering
		3. Standard MPA with pure JS sprinkled in for interactivity.
	- All services, caching, file storage, DB, backend server, etc. Should run a single machine in order to avoid network latency. If I ever need to solve issues with certain global regions hitting latency issues due to hosting location, I will scale horizontally, i.e. clone the machine and host it in multiple regions.
## Backend language
I'd like to learn more about go, so I'll use that.

## Backend web framework
I looked up top webframework and found [this article](https://blog.logrocket.com/5-top-go-web-frameworks) (in order of stars greatest to least)
1. [gin](https://github.com/gin-gonic/gin)
2. [beego](https://github.com/beego/beego)
3. [echo](https://github.com/labstack/echo)
4. [iris](https://github.com/kataras/iris)
5. [fiber](https://github.com/gofiber/fiber)


Since I'm new to golang, I'd prefer to use a monolithic type web framework with "all bells and whistles included." It seems that gin is a minimal style framework that depends on plugins and supporting libraries. E.g. it doesn't directly support websockets as best as I can tell.

Beego also doesn't directly support websockets, like gin it requires [gorilla](https://www.gorillatoolkit.org/).

I skipped looking into `echo` and `fiber` when I read this [issue](https://github.com/kataras/iris/issues/1396). Maybe not the most unbiased source, I know. But I didn't want to spend too much time on this step.


So I chose `iris`.

## Frontend

Goals
1. The only absolute requirement is load speed. I want the main bottleneck for `request->time-to-paint` to be the network, not JS. To quantify this, my goal is to make the [first contentful paint](https://web.dev/first-contentful-paint/) less than 1.2 seconds.
2. A secondary requirement is to have the backend to handle routing. Meaning the JS framework (if we choose one) will need play well with not owning the entire DOM.


If I were to use a JS framework it would likely be react. I already know enough react to create applications. However, the current version of react is [35kb gzipped](https://reactjs.org/blog/2017/09/26/react-v16.0.html#reduced-file-size) which pretty much rules that out. It's simply too large to guarantee our absolute requirement.

After a bit of googling I found that 
* [mithri.js](https://mithril.js.org/) is 10kb gzipped
* svelte [is apparently](https://pagepro.co/blog/react-vs-svelte) less than 2kb gzipped
* [backbone.js](https://backbonejs.org/) is 8kb gzipped

Initially thse seem small, but after seeing [this graph](https://github.com/sveltejs/svelte/issues/2546#issuecomment-678845774) I realized that most of the space will be taken up by my own components and libraries I've included.

In order to achieve goal number one, I've decided to go spartan and use backend templating with minimal vanilla JS. I'll try to inlcude as few libraries as possible. In the case of the need for some complex front end component, I'll allow for some lightweight libraries. I may want to optimize that from the getgo only to load these script/libraries for the pages that need them instead of creating a global bundle that will be loaded on every page.

So now that I've decided not to  use a frontend JS framework, I need to decide on a templating engine. This is made easy by iris's [builtin support](https://github.com/kataras/iris/wiki/View) for six templating languages.

1. std template/html
2. django
3. handlebars
4. amber
5. pug(jade)
6. jet



I consulted [this benchmark](https://github.com/SlinSo/goTemplateBenchmark) to help me get an understanding about speed.

I'm focusing less on speed than I am on usability. This is because my intuition tells me than rendering speed will be a low reward optimization in comparison to DB queries and network requests.

1. standard html template seems too low level. I want nice features.
2. I'm used to django syntax so I might just go with that.
3. Handlebars has helpers. I like that
4. I don't immediately understand amber syntax so that's out. 
5. jade seems to use tabination as part of its syntax. I don't want that. Although it looks to be the fastest one.
6. jet has a goland extension. I like that.

I'm going to go with django templating aka pongo2. It has helpers like handlebars and it's familiar to me. The only disadvantage is that I couldn't find an intellij plugin.

## Development, packaging and deployment
I've had sucess with the following setup in the past so I will keep it this way.

* Use `docker-compose` to tie together a set of services
* Each service gets its own configuration. Off of the top of my head , and subject to change, this will be
	- DB storage
	- In memory caching for websockets and IPC
	- Certbot for ssl certificate management
	- Nginx for load balancing and request caching
	- Backend (go appplication in our case)
	- Frontend JS 
	- Containerization service (for executing server side demo code)
	- Unified logging management
* Each service can have its own volume if needed. Some services will get access to other services' volumes. For example, nginx needs access to both its own volume, the js volume (to servce static asssets), and the certbot volume.
* Via simple bash scripts the `docker-compose` project will knowledgeable of two environments, `dev` and `prod`. The current environment will be passed on to each service  to allow them to modify their behavior based on the environment.
* Although there is something to be said against adding another layer of indirection, see [here](https://stackoverflow.com/a/17777630/4188138) for why I want to use nginx on top of go even though go can serve a web application just fine.
* CI will be github actions making sure that `docker-compose up` works and that the web application succeeds in returning a healthily status
* Deployment is a github action that runs a bash script. The bash script: 
	- copies source files to the server
	- copies secrets to the server
	- runs `docker-compose down`
	- runs `docker-compose up`
* During dev mode, the local file system is mounted to each service. Some services like the frontend and backend may want to watch for file changes and do application reloads/rebuilds.

## Containerization


### Code gen
Commonly used go code, grpc definitions, will be stored in the codegen directory, and copied to appropriate services.
Maybe we'll do proper package management in the future. But for now this is more fun.


### Cross platform
I decided early on to only support linux for both the target and development platform.
I can rely on POSIX and it greatly simplifies my life.

### Dependencies
You need `protoc` available on your PATH variable


## MISC
only difference between dev and prod compose files should be bind mounts. Don't modify dev directly. Generate it.

## CSS
Should I write from scratch? Maybe, but I definitely want tooling to help with typing, building, and code reuse.
SAAS seems to be a decent option. I don't know CSS very well and am not especially interested in it.
I likely won't use a CSS reset. I don't want to touch the default browser styles. I'll just use a CSS reset for the few elements that I need to style, if any.

* [tailwind](https://tailwindcss.com/) Popular CSS framework. It's too big to use. Clocks in at 90KB GZipped. I don't want to load that on every page.
* [purecss](https://purecss.io/)  4KB GZipped. Saw some SAAS tooling for this
* [milligram](https://milligram.io/)  2.5KB GZipped.
* [picnic](https://picnicss.com/)  8KB GZipped. Nice and colorful.
* [chota](https://jenil.github.io/chota/) 3.5KB GZipped.