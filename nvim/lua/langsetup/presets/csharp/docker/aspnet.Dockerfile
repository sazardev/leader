# ASP.NET Core: publish in the SDK image, run in the smaller ASP.NET runtime image
# target: Dockerfile
FROM mcr.microsoft.com/dotnet/sdk:{{channel}} AS build
WORKDIR /src
COPY . .
RUN dotnet restore
RUN dotnet publish -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:{{channel}} AS runtime
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "{{name}}.dll"]
