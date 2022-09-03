package main

import "os"

type Config struct {
	StaticDir string
}

func GetConfig() *Config {
	if os.Getenv("STAGE") == "dev" {
		// use live output from the frontend container
		return &Config{StaticDir: "/mnt/host/frontend/dist"}
	} else {
		// use the static output from the frontend build container
		return &Config{StaticDir: "/mnt/frontend/dist"}
	}
}
