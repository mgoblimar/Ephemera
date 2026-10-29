from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Proxy configuration, read from environment variables or a local .env file."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore", populate_by_name=True)

    use_real_providers: bool = False
    # Meta's docs call it MODEL_API_KEY; META_API_KEY is accepted too.
    meta_api_key: str | None = Field(default=None, validation_alias=AliasChoices("MODEL_API_KEY", "META_API_KEY"))
    meta_api_base_url: str = "https://api.meta.ai/v1"

    # One model per job (see SPEC 5.1 "Which model does what"). Defaults are the demo setup;
    # set the two text models to muse-spark-1.3-contributor in .env for cheap testing.
    agent_model: str = "muse-wonder-1.0"  # Theme Blend Agent: plan (tool loop) + layout
    vision_model: str = "muse-spark-1.3"  # detect items, OCR/tags, prompts & captions, style profile
    sam_model: str = "sam-3.1"  # cutouts: box prompts (auto-detect) and point prompts (taps)
    image_model: str = "muse-image-1.0"  # generated stamps, tape, labels

    max_upload_bytes: int = 10 * 1024 * 1024
    max_image_side: int = 1536
    image_ttl_seconds: int = 900
    rate_limit_per_minute: int = 60

    def validate_for_startup(self) -> None:
        """Fail fast when real providers are requested without credentials."""
        if self.use_real_providers and not self.meta_api_key:
            raise RuntimeError("USE_REAL_PROVIDERS=true requires MODEL_API_KEY (or META_API_KEY) to be set.")
