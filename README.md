Just run `measure.ps1`. It requires a specific version of dotnet SDK, but you can change it in `global.json`, it might change your results, as different runner is shipped with different versions of SDK.

```powershell
$classes = 100
$tests = 100
$tries = 5
```

The tests are generated. To add new version do 
```
mkdir Version16.9
cd Version16.9
dotnet new mstest
```

Then remove the UnitTests1.cs, and copy paste from other csproj, into the new csproj. Change just the Test.SDK package version to align with the name of the folder. 

## History
Runs and logs are stored in history directory, with the data in JSON format for later analysis. Change the ObjectVersion on the json object if you change the data in it so it can be distinguished later. 




