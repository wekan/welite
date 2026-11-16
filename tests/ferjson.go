// Test oracle: use FerretDB's real SJSON implementation, not a reimplementation.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"github.com/FerretDB/FerretDB/internal/handler/sjson"
	"github.com/FerretDB/FerretDB/internal/types"
	"math"
	"os"
	"time"
)

func mustDoc(values ...any) *types.Document {
	d, e := types.NewDocument(values...)
	if e != nil {
		panic(e)
	}
	return d
}
func mustArray(values ...any) *types.Array {
	a, e := types.NewArray(values...)
	if e != nil {
		panic(e)
	}
	return a
}
func emit(d *types.Document) {
	b, e := sjson.Marshal(d)
	if e != nil {
		panic(e)
	}
	fmt.Println(string(b))
}
func main() {
	if len(os.Args) > 1 && os.Args[1] == "seed" {
		emit(mustDoc("_id", "document", "title", "Original", "int", int32(-2147483648), "long", int64(9007199254740993), "longMin", int64(math.MinInt64), "longMax", int64(math.MaxInt64), "midFloat", float64(1e20), "double", math.Nextafter(1, 2), "negativeZero", math.Copysign(0, -1), "large", math.MaxFloat64, "small", math.SmallestNonzeroFloat64, "nan", math.NaN(), "plusInf", math.Inf(1), "minusInf", math.Inf(-1), "date", time.UnixMilli(-123456789).UTC(), "timestamp", types.Timestamp(math.MaxUint64), "binary", types.Binary{B: []byte{0, 255, 10, 13}, Subtype: types.BinaryUUID}, "objectId", types.ObjectID{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}, "regex", types.Regex{Pattern: "^test.*", Options: "im"}, "bool", true, "null", types.Null))
		profile := mustDoc("language", "fi", "date", time.UnixMilli(1794835200000).UTC(), "array", mustArray(int32(1), int64(2), time.UnixMilli(123456789).UTC(), mustDoc("nested", false)))
		emit(mustDoc("_id", "nested", "title", "日本語 <>& \" \\ \x00 😀", "profile", profile, "emptyObject", mustDoc(), "emptyArray", mustArray()))
		emit(mustDoc("_id", "keys", "dot.key", mustDoc("quoted\"key", "value", "dollar$key", int32(7)), "unicode-😀", mustArray("a", "b", mustArray(true, types.Null))))
		return
	}
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 32*1024*1024)
	for scanner.Scan() {
		doc, e := sjson.Unmarshal(scanner.Bytes())
		if e != nil {
			fmt.Println(`{"error":"invalid"}`)
			continue
		}
		if len(os.Args) > 1 && os.Args[1] == "bits" {
			bits := map[string]string{}
			for _, key := range doc.Keys() {
				value, e := doc.Get(key)
				if e != nil {
					panic(e)
				}
				if number, ok := value.(float64); ok {
					bits[key] = fmt.Sprintf("%016x", math.Float64bits(number))
				}
			}
			encoded, e := json.Marshal(bits)
			if e != nil {
				panic(e)
			}
			fmt.Println(string(encoded))
			continue
		}
		encoded, e := sjson.Marshal(doc)
		if e != nil {
			fmt.Println(`{"error":"invalid"}`)
			continue
		}
		// Emit both the exact semantic types and canonical data via FerretDB's own encoder.
		var parsed any
		if e = json.Unmarshal(encoded, &parsed); e != nil {
			panic(e)
		}
		fmt.Println(string(encoded))
	}
	if e := scanner.Err(); e != nil {
		panic(e)
	}
}
