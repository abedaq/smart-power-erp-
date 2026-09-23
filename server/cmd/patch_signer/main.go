package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "gen-keys":
		generateKeys()
	case "sign":
		signPatch(os.Args[2:])
	default:
		fmt.Printf("Unknown command: %s\n", command)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("SmartPower ERP - Developer Patch Signer & Key Tool")
	fmt.Println("Usage:")
	fmt.Println("  patch_signer gen-keys [-out-dir <directory>]")
	fmt.Println("  patch_signer sign -sql <file.sql> -hwid <target_hwid> [options]")
	fmt.Println("Options for sign:")
	fmt.Println("  -sql           Path to the SQL patch file (required)")
	fmt.Println("  -hwid          Target station HWID (required)")
	fmt.Println("  -type          Command type (default: RUN_SQL_PATCH)")
	fmt.Println("  -key           Hex private key or path to private key file")
	fmt.Println("  -min-ver       Minimum application version required (default: 1.0.0)")
	fmt.Println("  -max-ver       Maximum application version allowed (optional)")
	fmt.Println("  -ttl           Validity period in hours (default: 48)")
	fmt.Println("  -transactional Execute inside SQL transaction (default: true)")
	fmt.Println("  -out           Output path for the generated JSON command (optional)")
}

func generateKeys() {
	genFlags := flag.NewFlagSet("gen-keys", flag.ExitOnError)
	outDir := genFlags.String("out-dir", "keys", "Directory to save generated keys")
	_ = genFlags.Parse(os.Args[2:])

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating keypair: %v\n", err)
		os.Exit(1)
	}

	pubHex := hex.EncodeToString(pub)
	privHex := hex.EncodeToString(priv)

	if err := os.MkdirAll(*outDir, 0700); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create keys directory: %v\n", err)
		os.Exit(1)
	}

	privPath := filepath.Join(*outDir, "developer_private.key")
	pubPath := filepath.Join(*outDir, "developer_public.key")

	if err := os.WriteFile(privPath, []byte(privHex), 0600); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write private key: %v\n", err)
		os.Exit(1)
	}
	if err := os.WriteFile(pubPath, []byte(pubHex), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write public key: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("==================================================================")
	fmt.Println("✅ Successfully generated Ed25519 Keypair for SmartPower Developer")
	fmt.Println("==================================================================")
	fmt.Printf("Private Key saved to : %s\n", privPath)
	fmt.Printf("Public Key saved to  : %s\n", pubPath)
	fmt.Println("------------------------------------------------------------------")
	fmt.Printf("Master Public Key (Hex): %s\n", pubHex)
	fmt.Println("------------------------------------------------------------------")
	fmt.Println("⚠️  KEEP THE PRIVATE KEY SECRET! Embed the Public Key into Go code.")
	fmt.Println("==================================================================")
}

func signPatch(args []string) {
	signFlags := flag.NewFlagSet("sign", flag.ExitOnError)
	sqlPath := signFlags.String("sql", "", "Path to SQL file to sign (required)")
	targetHWID := signFlags.String("hwid", "", "Target HWID for the station (required)")
	cmdType := signFlags.String("type", "RUN_SQL_PATCH", "Command type")
	keyInput := signFlags.String("key", "", "Hex private key or path to developer_private.key")
	minVer := signFlags.String("min-ver", "1.0.0", "Minimum compatible app version")
	maxVer := signFlags.String("max-ver", "", "Maximum compatible app version")
	ttlHours := signFlags.Int("ttl", 48, "TTL in hours")
	transactional := signFlags.Bool("transactional", true, "Execute in a transaction")
	outPath := signFlags.String("out", "", "Output JSON file path (optional)")
	_ = signFlags.Parse(args)

	if *sqlPath == "" || *targetHWID == "" {
		fmt.Fprintln(os.Stderr, "Error: Both -sql and -hwid flags are required.")
		signFlags.Usage()
		os.Exit(1)
	}

	// 1. Read SQL file
	sqlBytes, err := os.ReadFile(*sqlPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to read SQL file '%s': %v\n", *sqlPath, err)
		os.Exit(1)
	}
	sqlContent := strings.TrimSpace(string(sqlBytes))
	if sqlContent == "" {
		fmt.Fprintln(os.Stderr, "Error: SQL file is empty.")
		os.Exit(1)
	}

	// 2. Resolve Private Key
	privKeyHex := *keyInput
	if privKeyHex == "" {
		// Look for default key file locations
		candidates := []string{
			"keys/developer_private.key",
			"tools/forensics/keys/developer_private.key",
			filepath.Join(os.Getenv("USERPROFILE"), ".smartpower", "developer_private.key"),
		}
		for _, c := range candidates {
			if data, err := os.ReadFile(c); err == nil {
				privKeyHex = strings.TrimSpace(string(data))
				fmt.Printf("🔑 Loaded private key from: %s\n", c)
				break
			}
		}
	} else if _, err := os.Stat(privKeyHex); err == nil {
		data, err := os.ReadFile(privKeyHex)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to read key file '%s': %v\n", privKeyHex, err)
			os.Exit(1)
		}
		privKeyHex = strings.TrimSpace(string(data))
	}

	if privKeyHex == "" {
		fmt.Fprintln(os.Stderr, "Error: No private key provided. Use -key or run 'gen-keys' first.")
		os.Exit(1)
	}

	privKeyBytes, err := hex.DecodeString(privKeyHex)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid hex private key: %v\n", err)
		os.Exit(1)
	}
	if len(privKeyBytes) != ed25519.PrivateKeySize {
		fmt.Fprintf(os.Stderr, "Invalid private key length (%d bytes, expected %d)\n", len(privKeyBytes), ed25519.PrivateKeySize)
		os.Exit(1)
	}

	// 3. Build Canonical Message: command_type|target_hwid|sql_content
	canonicalMessage := fmt.Sprintf("%s|%s|%s", *cmdType, *targetHWID, sqlContent)
	sigBytes := ed25519.Sign(privKeyBytes, []byte(canonicalMessage))
	signatureHex := hex.EncodeToString(sigBytes)

	// 4. Construct Command Payload for Supabase
	expiresAt := time.Now().Add(time.Duration(*ttlHours) * time.Hour).UTC().Format(time.RFC3339)

	commandPayload := map[string]interface{}{
		"target_hwid":     *targetHWID,
		"command_type":    *cmdType,
		"min_app_version": *minVer,
		"payload": map[string]interface{}{
			"sql":           sqlContent,
			"transactional": *transactional,
		},
		"signature":  signatureHex,
		"expires_at": expiresAt,
		"status":     "PENDING",
	}
	if *maxVer != "" {
		commandPayload["max_app_version"] = *maxVer
	}

	jsonBytes, err := json.MarshalIndent(commandPayload, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to marshal JSON: %v\n", err)
		os.Exit(1)
	}

	if *outPath != "" {
		if err := os.WriteFile(*outPath, jsonBytes, 0644); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to write output to '%s': %v\n", *outPath, err)
			os.Exit(1)
		}
		fmt.Printf("✅ Signed patch command written to: %s\n", *outPath)
	}

	fmt.Println("\n=== Signed Command JSON (Ready for Supabase) ===")
	fmt.Println(string(jsonBytes))
	fmt.Println("================================================")
	fmt.Printf("Signature (Hex): %s\n", signatureHex)
	fmt.Printf("Canonical Message Length: %d bytes\n", len(canonicalMessage))
}
