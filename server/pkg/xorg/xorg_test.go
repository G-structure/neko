//go:build !darwin

package xorg

import (
	"testing"

	"github.com/m1k1o/neko/server/pkg/types"
)

func TestScreenModeAlreadyActive(t *testing.T) {
	t.Parallel()

	requested := types.ScreenSize{Width: 1920, Height: 1080, Rate: 60}
	tests := []struct {
		name          string
		width         int
		height        int
		rate          int16
		alreadyActive bool
	}{
		{name: "exact", width: 1920, height: 1080, rate: 60, alreadyActive: true},
		{name: "rounded down", width: 1920, height: 1080, rate: 59, alreadyActive: true},
		{name: "rounded up", width: 1920, height: 1080, rate: 61, alreadyActive: true},
		{name: "different rate", width: 1920, height: 1080, rate: 58},
		{name: "driver mode id", width: 1920, height: 1080, rate: 50},
		{name: "different width", width: 1280, height: 1080, rate: 60},
		{name: "different height", width: 1920, height: 720, rate: 60},
		{name: "missing current rate", width: 1920, height: 1080, rate: 0},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if got := screenModeAlreadyActive(requested, test.width, test.height, test.rate); got != test.alreadyActive {
				t.Fatalf("screenModeAlreadyActive() = %t, want %t", got, test.alreadyActive)
			}
		})
	}
}
