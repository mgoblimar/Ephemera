from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Proxy configuration, read from environment variables or a local .env file."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    use_real_providers: bool = False
    meta_api_key: str | None = None
    meta_api_base_url: str = "https://api.meta.ai/v1"
    muse_wonder_model: str = "muse-wonder-1.0"

    max_upload_bytes: int = 10 * 1024 * 1024
    max_image_side: int = 1536
    image_ttl_seconds: int = 900
    rate_limit_per_minute: int = 60

    def validate_for_startup(self) -> None:
        """Fail fast when real providers are requested without credentials."""
        if self.use_real_providers and not self.meta_api_key:
            raise RuntimeError("USE_REAL_PROVIDERS=true requires META_API_KEY to be set.")
