/*
* SPDX-License-Identifier: BSD 2-Clause "Simplified" License
*
* nextctl.go
*
* Created by:	Aakash Sen Sharma, December 2022
* Copyright:	(C) 2022, Aakash Sen Sharma & Contributors
 */

package main

import (
	"fmt"
	"os"

	. "git.sr.ht/~shinyzenith/nextctl/pkg/next_control"
	"github.com/rajveermalviya/go-wayland/wayland/client"
)

const EXIT_FAILURE = 1
const EXIT_SUCCESS = 0
const VERSION = "0.1.0-dev"

type Nextctl struct {
	display      *client.Display
	registry     *client.Registry
	next_control *NextControlV1
}

const usage = `Usage: nextctl <command>
  -h, --help      Print this help message and exit.

  -v, --version   Print the version number and exit.

Complete documentation for recognized commands can be found in
the nextctl(1) man page.`

func main() {
	for _, arg := range os.Args[1:] {
		if arg == "-h" || arg == "--help" {
			fmt.Fprintln(os.Stderr, usage)
			os.Exit(0)
		} else if arg == "-v" || arg == "--version" {
			fmt.Fprintln(os.Stderr, "Nextctl version: ", VERSION)
			os.Exit(0)
		}
	}

	Nextctl := &Nextctl{display: nil, registry: nil, next_control: nil}

	if display, err := client.Connect(""); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR: Cannot connect to wayland display.")
		os.Exit(EXIT_FAILURE)
	} else {
		Nextctl.display = display
	}

	Nextctl.registry, _ = Nextctl.display.GetRegistry()
	Nextctl.registry.AddGlobalHandler(Nextctl.GlobalHandler)

	Nextctl.DisplayDispatch()

	if Nextctl.next_control == nil {
		fmt.Fprintln(os.Stderr, "ERROR: Compositor doesn't implement NextControlV1.")
		os.Exit(EXIT_FAILURE)
	}

	for _, arg := range os.Args[1:] {
		_ = Nextctl.next_control.AddArgument(arg)
	}
	callback, _ := Nextctl.next_control.RunCommand()
	callback.AddSuccessHandler(Nextctl.NextSuccessHandler)
	callback.AddFailureHandler(Nextctl.NextFailureHandler)
	Nextctl.DisplayDispatch()

	os.Exit(EXIT_SUCCESS)
}

func (Nextctl *Nextctl) DisplayDispatch() {
	callback, err := Nextctl.display.Sync()
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERROR: wayland dispatch failed.")
		os.Exit(EXIT_FAILURE)
	}
	defer func() {
		if err := callback.Destroy(); err != nil {
			fmt.Fprintln(os.Stderr, "ERROR: wayland dispatch failed.")
			os.Exit(EXIT_FAILURE)
		}
	}()

	callback_done := false
	callback.AddDoneHandler(func(_ client.CallbackDoneEvent) {
		callback_done = true
	})

	for !callback_done {
		Nextctl.display.Context().Dispatch()
	}
}

func (Nextctl *Nextctl) GlobalHandler(wl_global client.RegistryGlobalEvent) {
	if wl_global.Interface == "next_control_v1" {
		next_control := NewNextControlV1(Nextctl.display.Context())
		err := Nextctl.registry.Bind(wl_global.Name, wl_global.Interface, wl_global.Version, next_control)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERROR: wayland dispatch failed.")
			os.Exit(EXIT_FAILURE)
		}
		Nextctl.next_control = next_control
	}
}

func (Nextctl *Nextctl) NextSuccessHandler(success_event NextCommandCallbackV1SuccessEvent) {
	fmt.Fprintln(os.Stdout, success_event.Output)
}

func (Nextctl *Nextctl) NextFailureHandler(failure_event NextCommandCallbackV1FailureEvent) {
	fmt.Fprint(os.Stderr, "ERROR: ", failure_event.FailureMessage)
	if failure_event.FailureMessage == "Unknown command\n" || failure_event.FailureMessage == "No command provided\n" {
		fmt.Fprintln(os.Stderr, usage)
	}
}
