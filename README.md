Just run `measure.ps1`. It requires a specific version of dotnet SDK, but you can change it in `global.json`, it might change your results, as different runner is shipped with different versions of SDK.

```powershell
$classes = 100
$tests = 100
$tries = 5
```
## Adding new version



To add new version do: 
```
mkdir Version16.9
cd Version16.9
dotnet new mstest
```

Then remove the `UnitTests1.cs` because the tests are generated. Open the new `.csproj`. Delete everything. Copy paste from some other `.csproj`. Change just the `Test.SDK` package version to align with the name of the folder. 

## Tries

Try 1 will actually compile the DLL, because we delete all obj and bin on the top of `measure.ps1`. This is on purpose, to easily see how long does that take, and to have it in the historical data. 

**BUT** it also means that try 1 is not comparable with the rest of the tries. So don't compare 🍐 with 🍎.  

## History
Runs and logs are stored in history directory, with the data in JSON format for later analysis. Change the ObjectVersion on the json object if you change the data in it so it can be distinguished later. 




