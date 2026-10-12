package main

import (
	"encoding/csv"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"

	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
)

func main() {
	demoPath := `..\demos\mouz-vs-spirit-m1-dust2.dem`

	// Generate the output filename from the demo filename.
	matchName := filepath.Base(demoPath)
	matchName = matchName[:len(matchName)-len(filepath.Ext(matchName))]
	outputPath := matchName + "_snapshots.csv"

	out, err := os.Create(outputPath)
	if err != nil {
		log.Fatal("Could not create CSV: ", err)
	}
	defer out.Close()

	writer := csv.NewWriter(out)
	defer writer.Flush()

	// Write the CSV header.
	if err := writer.Write([]string{
		"tick",
		"round_num",
		"steamid",
		"name",
		"team",
		"alive",
		"health",
		"x",
		"y",
		"z",
	}); err != nil {
		log.Fatal("Could not write CSV header: ", err)
	}

	roundNum := 0
	roundActive := false
	nextSampleTick := 0
	sampleInterval := 320 // Approximately 5 seconds at 64 ticks per second.
	var writeErr error

	err = dem.ParseFile(demoPath, func(p dem.Parser) error {
		p.RegisterEventHandler(func(e events.RoundStart) {
			roundNum++
			roundActive = true
			nextSampleTick = p.GameState().IngameTick()
		})

		p.RegisterEventHandler(func(e events.RoundEnd) {
			roundActive = false
		})

		p.RegisterEventHandler(func(e events.FrameDone) {
			if !roundActive || writeErr != nil {
				return
			}

			state := p.GameState()
			tick := state.IngameTick()

			if tick < nextSampleTick {
				return
			}

			nextSampleTick = tick + sampleInterval

			for _, player := range state.Participants().Playing() {
				if player == nil {
					continue
				}

				pos := player.Position()

				row := []string{
					strconv.Itoa(tick),
					strconv.Itoa(roundNum),
					strconv.FormatUint(player.SteamID64, 10),
					player.Name,
					fmt.Sprint(player.Team),
					strconv.FormatBool(player.IsAlive()),
					strconv.Itoa(player.Health()),
					strconv.FormatFloat(float64(pos.X), 'f', 3, 64),
					strconv.FormatFloat(float64(pos.Y), 'f', 3, 64),
					strconv.FormatFloat(float64(pos.Z), 'f', 3, 64),
				}

				if err := writer.Write(row); err != nil {
					writeErr = err
					return
				}
			}
		})

		return nil
	})

	if err != nil {
		log.Fatal("Demo parsing failed: ", err)
	}

	writer.Flush()

	if err := writer.Error(); err != nil {
		log.Fatal("CSV write failed: ", err)
	}
	if writeErr != nil {
		log.Fatal("Snapshot write failed: ", writeErr)
	}

	fmt.Println("Demo parsed successfully!")
	fmt.Println("Rounds detected:", roundNum)
	fmt.Println("CSV saved to:", outputPath)
}
