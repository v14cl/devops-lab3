FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS builder
WORKDIR /workspace

COPY src/mywebapp/mywebapp.csproj src/mywebapp/
RUN dotnet restore "src/mywebapp/mywebapp.csproj"

COPY src/mywebapp/ src/mywebapp/

RUN dotnet publish "src/mywebapp/mywebapp.csproj" -c Release -o /publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /opt/mywebapp

EXPOSE 8000

RUN apk add --no-cache krb5-libs && \
    if ! grep -q '^app:' /etc/group; then addgroup -S app; fi && \
    if ! id -u app >/dev/null 2>&1; then adduser -S -G app app; fi && \
    mkdir -p /etc/mywebapp && \
    chown -R app:app /etc/mywebapp /opt/mywebapp

COPY config/config.json /etc/mywebapp/config.json
COPY --from=builder /publish .

USER app

ENTRYPOINT ["dotnet", "mywebapp.dll"]
