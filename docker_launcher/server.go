package main

import (
	"context"
	"docker_launcher/internal/generated/common_utils"
	pb "docker_launcher/internal/generated/docker_launcher"
	"encoding/json"
	"errors"
	"fmt"
	"google.golang.org/grpc"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

// max RAM all containers will take up at any given time is: MAX_USERSPACE_MEMORY_MB*MAX_CONCURRENT_CONTAINERS
var MAX_USERSPACE_MEMORY_MB = 100
var MAX_IO_PS_IN_MB = 10

// max CPU all containers will take up at any given time is: MAX_CPUS*MAX_CONCURRENT_CONTAINERS
var MAX_CPUS = 0.04
var MAX_CONCURRENT_CONTAINERS = 20
var MAX_DISK_GB = 1
var MAX_CONTAINER_AGE, _ = time.ParseDuration("1h")
var CONTAINER_LABEL = "resourceRestricted"
var mu = &sync.Mutex{}

type GRPCServer struct {
	pb.UnimplementedDockerLauncherServer
}

func (s *GRPCServer) RunningContainers(ctx context.Context, in *pb.Request) (*pb.ContainerArrayResponse, error) {
	containers, err := GetRunningContainers()

	returnContainers := []*pb.Container{}
	for _, container := range containers {
		returnContainers = append(returnContainers, &pb.Container{
			Id: container.Id,
		})
	}

	return &pb.ContainerArrayResponse{
		Containers: returnContainers,
	}, err
}

func (s *GRPCServer) PurgeExpiredContainers(ctx context.Context, in *pb.Request) (*pb.PurgeResponse, error) {
	killResults, errs := PurgeExpiredContainers()
	containers := []*pb.Container{}
	failures := 0
	errStrings := []string{}

	for _, killResult := range killResults {
		if killResult.Err == nil {
			containers = append(containers, &pb.Container{Id: killResult.Id})
		} else {
			errs = append(errs, killResult.Err)
			failures++
		}
	}
	for _, err := range errs {
		errStrings = append(errStrings, err.Error())
	}
	return &pb.PurgeResponse{
		Containers:  containers,
		NumFailures: int64(failures),
	}, errors.New(strings.Join(errStrings, ","))
}

func (s *GRPCServer) StartContainer(ctx context.Context, in *pb.Request) (*pb.Container, error) {
	id, err := StartContainer()
	if err != nil {
		return nil, err
	}
	return &pb.Container{
		Id: id,
	}, nil
}

func getAllBlockDevices() ([]string, error) {
	// call udevadm settle which according to lsblk man pages synchronizes devices before
	res := common_utils.NewCommand("udevadm", []string{"settle"}).WithVerbose().WithTreatStderrAsErr().Run()
	if res.Err != nil {
		return []string{}, res.Err
	}

	res = common_utils.NewCommand("lsblk",
		[]string{
			// without nodeps, dockers runs into unknown device errors. Apparently it cannot talk to slave devices.
			"--output=NAME", "--sort=NAME", "--raw", "--all", "--nodeps",
		}).WithVerbose().WithTreatStderrAsErr().Run()
	if res.Err != nil {
		return []string{}, res.Err
	}
	/*
		output is something like. We want everything but NAME.
			NAME
			loop0
			loop1
			loop10
			...
	*/
	deviceNamesDirty := strings.Split(string(res.Stdout.Bytes()), "\n")[1:]
	deviceNamesCleaned := []string{}
	for _, devName := range deviceNamesDirty {
		if devName != "" {
			deviceNamesCleaned = append(deviceNamesCleaned, devName)
		}
	}
	return deviceNamesCleaned, nil
}

type RunningContainer struct {
	Id        string
	Names     string
	CreatedAt string
}

type KillResult struct {
	Id  string
	Err error
}

func (rc *RunningContainer) ElapsedTimeSinceCreation() (time.Duration, error) {
	// somewhat of an unconvential layout. Includes timezone offset and abbreviation.
	// sample input : "2022-08-18 15:46:36 +0300 IDT"
	layout := "2006-01-02 15:04:05 -0700"
	givenTimeSplitBySpace := strings.Split(rc.CreatedAt, " ")
	if len(givenTimeSplitBySpace) < 2 {
		return 0, errors.New("Invalid CreatedAt string")
	}
	readyForParse := strings.Join(givenTimeSplitBySpace[:len(givenTimeSplitBySpace)-1], " ")
	createdAtAsTime, err := time.Parse(layout, readyForParse)
	if err != nil {
		return 0, err
	}
	return time.Since(createdAtAsTime), nil
}

type DockerRunCmd struct {
	maxCPU          string
	maxIOReads      []string
	maxIOWrites     []string
	maxMemory       string
	maxMemorySwap   string
	storageOptions  []string
	securityOptions []string
}

func (d *DockerRunCmd) Limits() []string {
	limitArgs := []string{
		d.maxCPU, d.maxMemory, d.maxMemorySwap,
	}
	limitArgs = append(limitArgs, d.maxIOReads...)
	limitArgs = append(limitArgs, d.maxIOWrites...)
	limitArgs = append(limitArgs, d.securityOptions...)
	limitArgs = append(limitArgs, d.storageOptions...)
	return limitArgs
}

func (d *DockerRunCmd) ContainerCmd() []string {
	return []string{"ubuntu", "sleep", "10"}
}

func (d *DockerRunCmd) AsCmd() *common_utils.Command {
	finalArgs := []string{"run"}
	// TODO read https://docs.docker.com/engine/security/

	finalArgs = append(finalArgs, d.Limits()...)
	finalArgs = append(finalArgs, "--detach")
	finalArgs = append(finalArgs, "--rm")
	finalArgs = append(finalArgs, "--label="+CONTAINER_LABEL)
	finalArgs = append(finalArgs, d.ContainerCmd()...)
	return common_utils.NewCommand(
		"docker", finalArgs,
	)
}

func KillDockerContainer(containerId string, resultChan chan<- KillResult) {

	res := common_utils.NewCommand("docker", []string{
		"rm", "--force", containerId,
	}).WithVerbose().WithTreatStderrAsErr().Run()
	resultChan <- KillResult{
		Id:  containerId,
		Err: res.Err,
	}
}

func PurgeExpiredContainers() ([]KillResult, []error) {
	containers, err := GetRunningContainers()
	errs := []error{}
	wg := sync.WaitGroup{}
	killResults := []KillResult{}
	killResultChan := make(chan KillResult, len(containers))
	numExpiredContainer := 0
	if err != nil {
		return []KillResult{}, []error{
			fmt.Errorf("Error when trying to purge old containers. Could not get running containers: %s", err.Error()),
		}
	}
	for _, container := range containers {
		elapsed, err := container.ElapsedTimeSinceCreation()
		if err != nil {
			errs = append(errs, fmt.Errorf("Error when trying to purge old containers. Container with Id: %s does not have a valid CreatedAt timestamp. %s. Original error: %e", container.Id, container.CreatedAt, err.Error()))
			continue
		}
		if elapsed > MAX_CONTAINER_AGE {
			numExpiredContainer++
			wg.Add(1)
			go func(containerId string, killResultChan chan KillResult, wg *sync.WaitGroup) {
				KillDockerContainer(containerId, killResultChan)
				wg.Done()
			}(container.Id, killResultChan, &wg)
		}
	}

	wg.Wait()

	for i := 0; i < numExpiredContainer; i++ {
		killResults = append(killResults, <-killResultChan)
	}
	close(killResultChan)

	return killResults, errs
}

func GetRunningContainers() ([]RunningContainer, error) {

	jsonError := func(err error, jsonLine string) error {
		return errors.New(fmt.Sprintf("Error trying to coerce docker stdout to json: %s. Original JSON: %s", err.Error(), jsonLine))
	}

	runningContainers := []RunningContainer{}
	res := common_utils.NewCommand(
		"docker",
		[]string{
			"container", "ls",
			// ids are fully qualified
			"--no-trunc",
			"--filter", "label=" + CONTAINER_LABEL,
			"--format", `{"Id":"{{ .ID }}","Names": "{{ .Names }}", "CreatedAt":"{{ .CreatedAt }}"}`,
		},
	).WithVerbose().WithTreatStderrAsErr().Run()

	jsonLinesDirty := strings.Split(string(res.Stdout.Bytes()), "\n")
	jsonLinesClean := []string{}
	for _, jsonLine := range jsonLinesDirty {
		if jsonLine != "" {
			jsonLinesClean = append(jsonLinesClean, jsonLine)
		}
	}

	for _, jsonLine := range jsonLinesClean {
		containerData := RunningContainer{}
		err := json.Unmarshal([]byte(jsonLine), &containerData)
		if err != nil {
			return []RunningContainer{}, jsonError(err, jsonLine)
		}

		runningContainers = append(runningContainers, containerData)
	}

	return runningContainers, nil
}

func (d *DockerRunCmd) Init() error {
	deviceNames, err := getAllBlockDevices()
	if err != nil {
		return err
	}
	// according to https://stackoverflow.com/a/67216311 this shouldn't hurt anything
	for _, devName := range deviceNames {
		d.maxIOReads = append(d.maxIOReads, fmt.Sprintf("--device-read-bps=/dev/%s:%dmb", devName, MAX_IO_PS_IN_MB))
		d.maxIOWrites = append(d.maxIOWrites, fmt.Sprintf("--device-write-bps=/dev/%s:%dmb", devName, MAX_IO_PS_IN_MB))
	}

	d.maxMemory = "--memory=" + strconv.Itoa(MAX_USERSPACE_MEMORY_MB) + "mb"
	// We are disabling swap memory.
	// According to https://docs.docker.com/config/containers/resource_constraints
	// If --memory-swap is set to the same value as --memory, and --memory is set to a positive integer, the container does not have access to swap.
	d.maxMemorySwap = "--memory-swap=" + strconv.Itoa(MAX_USERSPACE_MEMORY_MB) + "mb"
	// since swap is zero, I'm assuming I can ignore the "--memory-swappiness" argument

	// I would have added the "--kernel-memory" here in fear that a user could find a way of obtaining unlimited memory via the kernel, but it's been deprecated.

	d.maxCPU = "--cpus=" + fmt.Sprintf("%f", MAX_CPUS)

	// TODO, do we need to do this? it prevents in container privilege escalation such as sudo. But do we care if they have sudo?
	d.securityOptions = []string{
		"--security-opt=no-new-privileges",
	}

	// TODO comment this back in when we have automation that guarantees an xfs backed filesystem which is a requirement for using this option
	//d.storageOptions = []string{
	//	"--storage-opt", "size=" + strconv.Itoa(MAX_DISK_GB) + "G",
	//}
	d.storageOptions = []string{}

	return nil
}

func StartContainer() (string, error) {
	mu.Lock()
	containerIds, err := GetRunningContainers()
	if len(containerIds) > MAX_CONCURRENT_CONTAINERS {
		mu.Unlock()
		return "", errors.New("Too many container running")
	}
	mu.Unlock()

	dockCmd := DockerRunCmd{}
	err = dockCmd.Init()
	if err != nil {
		return "", errors.New(fmt.Sprintf("Critical error when attempting to build the docker command: %v\n", err))

	}

	res := dockCmd.AsCmd().Run()
	if res.Err != nil {
		return "", errors.New(fmt.Sprintf("Critical error when attempting to run the docker command: %v", err))

	}
	containerId := string(res.Stdout.Bytes())
	if len(containerId) == 0 {
		return "", errors.New("Could not get a container id from docker")
	}
	return strings.ReplaceAll(containerId, "\n", ""), nil
}

func StartGRPCServer() {
	lis, err := net.Listen("tcp", ":9000")
	if err != nil {
		panic(err)
	}

	grpcServer := grpc.NewServer()
	pb.RegisterDockerLauncherServer(
		grpcServer,
		&GRPCServer{},
	)
	log.Println("Starting gRPC server on port 9000")
	err = grpcServer.Serve(lis)
	if err != nil {
		panic(err)
	}

}

func main() {
	StartGRPCServer()
}
