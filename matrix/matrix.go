package matrix

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

var requiredColumns = []string{
	"Project",
	"GitHub repository",
	"Default branch",
	"Role",
	"Branch protection state",
	"Current workflow files",
	"Shared caller workflow path",
	"Required check-run names",
	"Release trigger",
	"Tag pattern",
	"DEB/RPM artifacts",
	"Arch package names",
	"Void package names",
	"Architectures",
	"Licence file SPDX",
	"Licence metadata surfaces",
	"Release shape",
	"Packaging source ref",
}

type Row struct {
	Cells map[string]string
}

func ReadFile(path string) ([]Row, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return Parse(f)
}

func Parse(r io.Reader) ([]Row, error) {
	scanner := bufio.NewScanner(r)
	var columns []string
	var rows []Row
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.HasPrefix(line, "|") || !strings.HasSuffix(line, "|") {
			if columns != nil {
				break
			}
			continue
		}
		cells := splitRow(line)
		if columns == nil {
			if !contains(cells, "Project") || !contains(cells, "GitHub repository") || !contains(cells, "Default branch") {
				continue
			}
			columns = cells
			continue
		}
		if isSeparator(cells) {
			continue
		}
		if len(cells) != len(columns) {
			return nil, fmt.Errorf("matrix row has %d cells; header has %d", len(cells), len(columns))
		}
		row := Row{Cells: make(map[string]string, len(columns))}
		for i, column := range columns {
			row.Cells[column] = cells[i]
		}
		rows = append(rows, row)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if columns == nil {
		return nil, fmt.Errorf("matrix table not found")
	}
	return rows, nil
}

func splitRow(line string) []string {
	parts := strings.Split(strings.Trim(line, "|"), "|")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	return parts
}

func contains(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

func isSeparator(cells []string) bool {
	for _, cell := range cells {
		if strings.Trim(cell, " :-") != "" {
			return false
		}
	}
	return true
}
