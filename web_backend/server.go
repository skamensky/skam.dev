package main

import (
	"github.com/kataras/iris/v12"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"log"
	pb "server/internal/generated/docker_launcher"
)

func GetDockerLaunchClient() (pb.DockerLauncherClient, *grpc.ClientConn, error) {
	// TODO remove the insecure part
	conn, err := grpc.Dial("docker_dns_docker_launcher:9000", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, nil, err
	}
	return pb.NewDockerLauncherClient(conn), conn, nil
}

func AddDockerRoutes(app *iris.Application) {
	docker := app.Party("/docker")
	docker.Handle("POST", "/start-container", func(ctx iris.Context) {
		client, conn, err := GetDockerLaunchClient()

		if err != nil {
			ctx.StatusCode(500)
			ctx.JSON(iris.Map{"errors": []string{err.Error()}, "data": nil})
			return
		}

		defer conn.Close()

		containerId, err := client.StartContainer(ctx.Request().Context(), &pb.Request{})

		if err != nil {
			ctx.StatusCode(400)
			ctx.JSON(iris.Map{"errors": []string{err.Error()}, "data": nil})
		} else {
			ctx.JSON(iris.Map{"errors": nil, "data": iris.Map{"containerId": containerId}})
		}
	})
	docker.Handle("GET", "/running-containers", func(ctx iris.Context) {
		client, conn, err := GetDockerLaunchClient()

		if err != nil {
			ctx.StatusCode(500)
			ctx.JSON(iris.Map{"errors": []string{err.Error()}, "data": nil})
			return
		}

		defer conn.Close()
		runningContainers, err := client.RunningContainers(ctx.Request().Context(), &pb.Request{})
		if err != nil {
			ctx.StatusCode(400)
			ctx.JSON(iris.Map{"errors": []string{err.Error()}, "data": nil})
		} else {
			ctx.JSON(iris.Map{"errors": nil, "data": iris.Map{"runningContainers": runningContainers}})
		}
	})
	docker.Handle("POST", "/purge-expired-containers", func(ctx iris.Context) {
		client, conn, err := GetDockerLaunchClient()

		if err != nil {
			ctx.StatusCode(500)
			ctx.JSON(iris.Map{"errors": []string{err.Error()}, "data": nil})
			return
		}

		defer conn.Close()
		purgedContainers, err := client.PurgeExpiredContainers(ctx.Request().Context(), &pb.Request{})

		if err != nil {
			ctx.StatusCode(500)
		}
		ctx.JSON(iris.Map{"errors": err, "data": purgedContainers})
		return
	})
}

func main() {
	config := GetConfig()
	app := iris.Default()
	AddDockerRoutes(app)
	app.Use(iris.Gzip)
	tmpl := iris.HTML("./views", ".gohtml") //todo update journey that we want to learn golang tempalates, and html contains helpers anyway
	tmpl.Reload(true)                       //todo add if-debug
	tmpl.AddFunc("printHelloWorld", func() string {
		return "Hello, from a template function!"
	})
	tmpl.AddFunc("printHelloWorldWithContext", func(data string) string {
		return "Hello, " + data + "!"
	})
	app.RegisterView(tmpl)

	app.Get("/index.html", func(ctx iris.Context) {
		ctx.ViewData("name", "Shmuel")
		err := ctx.View("index.gohtml")
		// todo abstract this into a handler that supports either json or html
		if err != nil {
			ctx.StatusCode(500)
			log.Printf("Error rendering view: %v. Context: %v", err, ctx)
			ctx.WriteString("<h1>500 server error</h1>")
		}
	})

	app.HandleDir("/static", config.StaticDir)
	app.Get("favicon.ico", func(ctx iris.Context) {
		err := ctx.SendFile("./views/favicon.ico", "favicon.ico")
		if err != nil {
			ctx.StatusCode(500)
			log.Printf("Error rendering view: %v. Context: %v", err, ctx)
			ctx.WriteString("<h1>500 server error</h1>")
		}
	})
	app.Listen(":8080")
}
