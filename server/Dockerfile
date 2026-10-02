# Base images are pinned to immutable multi-platform index digests; the tag records the reviewed version.
# mcr.microsoft.com/dotnet/sdk:10.0.401
FROM mcr.microsoft.com/dotnet/sdk:10.0.401@sha256:35d40304542c8689331f8cab17c65926cdf48fe711e289321d71924b230a7d29 AS build
# The release workflow passes the tag's version; GET /v1/server reports it.
ARG JOURNAL_VERSION=0.0.0-dev
WORKDIR /src
# .editorconfig carries the same analyzer configuration as local and CI builds.
COPY global.json Directory.Build.props .editorconfig ./
COPY server/src/Journal.Api/Journal.Api.csproj server/src/Journal.Api/packages.lock.json server/src/Journal.Api/
RUN dotnet restore server/src/Journal.Api/Journal.Api.csproj --locked-mode
COPY server/src/Journal.Api/ server/src/Journal.Api/
RUN dotnet publish server/src/Journal.Api/Journal.Api.csproj -c Release --no-restore -o /out /p:UseAppHost=false "/p:Version=$JOURNAL_VERSION"
# mcr.microsoft.com/dotnet/aspnet:10.0.12
FROM mcr.microsoft.com/dotnet/aspnet:10.0.12@sha256:2d584d8147faddb0d678c5748d47953e5b8e18621ed4fb7049a91381d9d7746f
WORKDIR /app
COPY --from=build /out .
# The same license and notices as the server packages.
COPY LICENSE NOTICE ./
COPY apps/apple/JournalApp/Resources/ThirdPartyNotices.txt THIRD-PARTY-NOTICES.txt
# APP_UID is the base image's nonroot "app" user. A numeric user lets orchestrators verify runAsNonRoot.
RUN mkdir /data && chown "$APP_UID:$APP_UID" /data
# `docker compose exec journal setup-code` shows the setup code. Owned by root, so the app user can't change it.
RUN printf '#!/bin/sh\nexec dotnet /app/Journal.Api.dll --setup-code "$@"\n' > /usr/local/bin/setup-code && chmod 0755 /usr/local/bin/setup-code
USER $APP_UID
ENV ASPNETCORE_URLS=http://+:8080 Journal__DataDirectory=/data DOTNET_EnableDiagnostics=0
EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD ["dotnet", "Journal.Api.dll", "--health-check"]
ENTRYPOINT ["dotnet", "Journal.Api.dll"]
