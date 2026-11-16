package main
import("encoding/json";"os";"golang.org/x/crypto/bcrypt")
type Input struct{Password string;Cost int;Hash string}
func main(){var in Input;if err:=json.NewDecoder(os.Stdin).Decode(&in);err!=nil{panic(err)};if in.Hash!=""{json.NewEncoder(os.Stdout).Encode(bcrypt.CompareHashAndPassword([]byte(in.Hash),[]byte(in.Password))==nil);return};hash,err:=bcrypt.GenerateFromPassword([]byte(in.Password),in.Cost);if err!=nil{panic(err)};json.NewEncoder(os.Stdout).Encode(string(hash))}
