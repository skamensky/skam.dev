package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/robfig/cron"
	"io/ioutil"
	"log"
	"net/http"
	"reflect"
	"runtime"
	"time"
)

var DOCKER_URL = "http://127.0.0.1:8080/"

func PurgeExpiredContainers() error {
	client := http.Client{}
	buff := bytes.Buffer{}
	resp, err := client.Post(DOCKER_URL+"purge-expired-containers", "application/json", &buff)
	if err != nil {
		return errors.New(fmt.Sprintf("Error making request: %s", err.Error()))
	}
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return errors.New(fmt.Sprintf("Error reading request response %s", err.Error()))
	}
	jsonData := make(map[string]interface{})
	err = json.Unmarshal(body, &jsonData)
	bodyString := string(body)
	if len(bodyString) > 0 && bodyString[len(bodyString)-1] != '\n' {
		bodyString += "\n"
	}
	log.Print(bodyString)

	if resp.StatusCode != 200 {
		log.Printf("WARNING: Response StatusCode ==%d\n", resp.StatusCode)
	}
	return nil
}

func LogDecorator(job func() error) func() {
	// from https://stackoverflow.com/a/7053871
	wrapper := func() {
		funcName := runtime.FuncForPC(reflect.ValueOf(job).Pointer()).Name()
		log.Printf("Running %s\n", funcName)
		start := time.Now()
		err := job()
		end := time.Now()
		duration := int(end.Sub(start).Seconds())

		statusMessage := "Job Completed Successfully"
		if err != nil {
			statusMessage = fmt.Sprintf("Job Failed. Error: %s", err.Error())
		}
		durationMessage := fmt.Sprintf("Job took %d seconds to complete", duration)
		log.Printf("%s. %s.", statusMessage, durationMessage)
	}
	return wrapper
}

func InitCrons() (*cron.Cron, error) {
	cronScheduler := cron.New()
	err := cronScheduler.AddFunc("@every 1m", LogDecorator(PurgeExpiredContainers))
	if err != nil {
		return nil, err
	}
	cronScheduler.Start()
	log.Println("Cron server started")
	return cronScheduler, nil
}

func main() {
	cronScheduler, err := InitCrons()
	defer cronScheduler.Stop()
	if err != nil {
		panic(err)
	}
	for {
		time.Sleep(1 * time.Second)
	}
}
