# Data Science / ML Project

## Stack

Python. Check `requirements.txt` or `pyproject.toml` for pinned versions of key libraries (numpy, pandas, scikit-learn, torch, etc.).

## Environment

- Always activate the project's virtual environment or conda environment before running any script. Never run with the system Python.
- Confirm which environment is active: `which python` or `conda info --envs`.
- Never modify the global Python environment.

## Dependencies

- Pin exact versions in `requirements.txt` using `pip freeze > requirements.txt` after testing.
- Separate concerns: `requirements.txt` for runtime, `requirements-dev.txt` for dev tools (pytest, black, ruff, jupyter).
- For conda: commit `environment.yml` with pinned versions. Regenerate with `conda env export --no-builds > environment.yml`.

## Data

- Never commit raw datasets to git. Add these patterns to `.gitignore`:
  ```
  *.csv
  *.parquet
  *.pkl
  *.h5
  *.hdf5
  *.feather
  data/raw/
  data/interim/
  data/processed/
  ```
- Reference data via paths in a config file or environment variables, not hardcoded absolute paths.
- Document data provenance (source, version, download date) in `data/README.md` or a DVC `.dvc` file.

## Notebooks

- Clear all outputs before committing Jupyter notebooks:
  ```bash
  jupyter nbconvert --clear-output --inplace notebooks/*.ipynb
  ```
- Notebooks are for exploration only. Finalized logic must be moved to `.py` modules before it's used in pipelines.
- Use `nbmake` or `papermill` for tested, parametrized notebook execution — don't run notebooks manually in CI.

## Reproducibility

- Set random seeds at the top of every experiment script:
  ```python
  import random, numpy as np
  random.seed(42)
  np.random.seed(42)
  # torch.manual_seed(42)  # if using PyTorch
  # tf.random.set_seed(42)  # if using TensorFlow
  ```
- Log hyperparameters and seeds with MLflow, W&B, or a plain JSON file next to the run output.
- Use `DVC` or explicit versioned paths for datasets and model checkpoints referenced in experiments.

## Models

- Save with version and timestamp: `model_v1_20240415T1423.pt`, never `model_final.pt` or `model.pkl`.
- Never overwrite an existing checkpoint. Always write to a new path.
- Document the training run (data version, hyperparameters, metrics) in a sidecar `.json` file with the same base name as the checkpoint.

## Privacy

- Before logging any DataFrame or running EDA, check for PII columns (names, email addresses, phone numbers, national IDs, IP addresses).
- Use column-level checks:
  ```python
  pii_patterns = ['name', 'email', 'phone', 'ssn', 'address', 'ip']
  flagged = [c for c in df.columns if any(p in c.lower() for p in pii_patterns)]
  ```
- Mask or drop PII before passing DataFrames to loggers, MLflow, or W&B.

## Credentials

- Use environment variables for all external service credentials (S3, GCS, BigQuery, database connections, API keys).
- Load via `os.environ` or `python-dotenv` from a `.env` file that is `.gitignored`.
- Never hardcode credentials, bucket names, or connection strings in code.

## Code quality

```bash
ruff check .            # linting (fast, replaces flake8 + isort + pyupgrade)
black --check .         # formatting check
pytest tests/           # run test suite
```

All three must pass before marking a task complete.

## Project structure

```
project/
  data/          # gitignored raw/interim/processed data
  notebooks/     # exploration only, outputs cleared before commit
  src/           # importable Python package
    features/    # feature engineering
    models/      # model definitions and training scripts
    pipelines/   # end-to-end pipeline code
  tests/         # pytest tests for src/
  models/        # saved checkpoints (gitignored or DVC-tracked)
  reports/       # generated reports and figures
```
