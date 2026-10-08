# Running the nf-dnaseq pipeline

**[nf-dnaseq](https://github.com/EIT-GBI/nf-dnaseq)** takes paired FASTQ files
and gives you back:

- trimmed, quality-checked reads (fastp + FastQC reports)
- reads aligned to your reference genome (sorted BAM files)
- coverage tracks you can load in a genome browser (bigWig)
- variant calls (VCF) and a consensus sequence

You will normally run it on the **GBI cluster** (Part 1). You can also run it
on your own computer (Part 2), which is handy for trying it out on small data.
You do not need to know Nextflow, and you do not need to write any code.

---

## Contents

- [Which way should I run it?](#which-way-should-i-run-it)
- [Words you will see](#words-you-will-see)
- **[Part 1 — Running on the GBI cluster](#part-1--running-on-the-gbi-cluster)**
  - [Before you start](#before-you-start)
  - [More words you will see](#more-words-you-will-see)
  - [Step 1 — Log in](#step-1--log-in)
  - [Step 2 — Check your setup works (5 minutes, recommended)](#step-2--check-your-setup-works-5-minutes-recommended)
  - [Optional — A practice run with example data](#optional--a-practice-run-with-example-data)
  - [Step 3 — Make your working folder](#step-3--make-your-working-folder)
  - [Step 4 — Put your reference genome in place](#step-4--put-your-reference-genome-in-place)
    - [Large genomes: index once](#large-genomes-index-once)
  - [Step 5 — Create your two settings files](#step-5--create-your-two-settings-files)
    - [The settings file you edit](#the-settings-file-you-edit)
    - [The settings file you do not edit](#the-settings-file-you-do-not-edit)
  - [Step 6 — Start the run](#step-6--start-the-run)
  - [Step 7 — Check how it is going](#step-7--check-how-it-is-going)
  - [Step 8 — Collect your results](#step-8--collect-your-results)
  - [Running it again](#running-it-again)
  - [If something goes wrong (on the cluster)](#if-something-goes-wrong-on-the-cluster)
- **[Part 2 — Running on your own computer](#part-2--running-on-your-own-computer)**
  - [What you can and cannot do here](#what-you-can-and-cannot-do-here)
  - [Step 1 — Install Docker](#step-1--install-docker)
  - [Step 2 — Install Java and Nextflow](#step-2--install-java-and-nextflow)
  - [Step 3 — Check it works](#step-3--check-it-works)
  - [Optional — A practice run with example data](#optional--a-practice-run-with-example-data-1)
  - [Step 4 — Set up your own run](#step-4--set-up-your-own-run)
  - [Step 5 — Run it](#step-5--run-it)
  - [Step 6 — Your results](#step-6--your-results)
  - [If something goes wrong (on your computer)](#if-something-goes-wrong-on-your-computer)

---

## Which way should I run it?

| | **Part 1 — the GBI cluster** | **Part 2 — your own computer** |
| --- | --- | --- |
| Good for | real datasets, large genomes, many samples | trying out the pipeline or its settings on small genomes (viral, bacterial) |
| Genome size | any, including human and mouse | up to a few hundred Mb |
| Samples | as many as you like, run in parallel | one or two |
| GPU steps | available | not available |
| Set-up effort | nothing to install | install Docker + Nextflow once |
| Speed | limited by how busy the cluster is | limited by your laptop |

**Use Part 1, the cluster, for your analyses.** Part 2 is optional.

---

## Words you will see

You can skip this and come back to it.

| Word | What it means here |
| --- | --- |
| **Nextflow** | The program that runs the pipeline. It reads the recipe and runs each step in the right order. |
| **container** | A sealed box holding a tool and everything it needs. The pipeline downloads these for you, so you never install bwa, samtools and so on yourself. |
| **Docker** | The program that runs containers on your own computer. On the cluster this is already taken care of for you. |
| **profile** | Which setup to use, chosen with `-profile`. `cluster` means "run on the cluster"; `docker` means "run on this computer with Docker". |
| **params file** | A small text file holding your settings — where your data is, where results go. This is the file you edit. |

---
---

# Part 1 — Running on the GBI cluster

## Before you start

You need:

1. **A Sandpit account you can log into.** If you do not have one yet, follow
   the [access and account setup guide](https://github.com/EIT-GBI/scientific-computing-docs/blob/main/sections/access.md),
   then the [SSH access guide](https://github.com/EIT-GBI/scientific-computing-docs/blob/main/sections/ssh.md).
2. **Your FASTQ files, already on the cluster.** If they are still in Object
   Storage, bring them across with the
   [moving data guide](https://github.com/EIT-GBI/scientific-computing-docs/blob/main/sections/moving-data/README.md).
3. **A reference genome** (a `.fasta` file) for your organism.

You also need the `nextflow` module. Check it is there:

```bash
module avail nextflow
```

If that lists nothing, the module has not been rolled out yet — ask the platform
team.

## More words you will see

| Word | What it means here |
| --- | --- |
| **login node** | The computer you land on when you log in. Use it to type commands and edit files. Do **not** run big analyses here. |
| **compute node** | The powerful machines that do the actual work. You never log into these — you send jobs to them. |
| **Slurm** | The booking system that decides which compute node runs your work, and when. |
| **job** | One piece of work you hand to Slurm. `sbatch` sends a job; `squeue` shows your jobs. |
| **partition** | A group of compute nodes. `cpu` is the normal one; `gpu` has graphics cards for the fast alignment steps. |
| **module** | How software is made available. `module load nextflow` puts Nextflow on your path. |
| **Lustre** | The fast shared disk at `/mnt/lustre`. It is for data you are actively computing on, not for storage. Lustre is expensive, so it cannot simply be made bigger — it only stays usable if everyone moves finished work off it. |

> **Golden rule for Lustre: never copy data from one place on Lustre to another.**
> Every copy takes up the same expensive space a second time. If your FASTQ files
> or genome are already somewhere under `/mnt/lustre`, point the pipeline at them
> where they are, or make a shortcut (`ln -s`) — Steps 3 and 4 show how. Only copy
> data *onto* Lustre when it lives somewhere else (Object Storage, your laptop).

One thing worth understanding, because the rest of Part 1 depends on it:

> When you start a run, you submit **one** Slurm job. That job is Nextflow
> itself. Nextflow then sits there and submits **more** Slurm jobs, one per
> pipeline step, and waits for them. So `squeue` will show one long-running job
> plus a changing set of short ones. That is normal.

---

## Step 1 — Log in

```bash
sft login --team eitoxford
ssh sandpit-tokyo-login
```

If `ssh sandpit-tokyo-login` does not work, you have not set up your SSH config
yet — see the [SSH access guide](https://github.com/EIT-GBI/scientific-computing-docs/blob/main/sections/ssh.md).
You can also use the **Tokyo Login Shell** in your browser from
[https://tokyo.eit-gbi.science](https://tokyo.eit-gbi.science).

---

## Step 2 — Check your setup works (5 minutes, recommended)

Run the built-in test dataset first. If this works, any later problem is about
your data rather than your setup.

```bash
mkdir -p /mnt/lustre/users/$USER/nf-test
cd /mnt/lustre/users/$USER/nf-test

echo "workflow.output.mode = 'link'" > lustre.config

module load nextflow
sbatch -J nf-test -p cpu -t 04:00:00 \
  --wrap='nextflow run EIT-GBI/nf-dnaseq -latest -profile test,cluster -c lustre.config -resume'
```

`-profile test,cluster` means "use the built-in test data, and run on the
cluster". `module load nextflow` comes first because the job picks up Nextflow
from your session when you submit it.

Check on it now and again with `squeue -u $USER`; once it no longer appears
there, read the log with `tail -30 slurm-<job number>.out`.

**You should see:**

```text
Succeeded   : 21
```

If you do, everything works. You can delete this folder.

---

## Optional — A practice run with example data

Step 2 runs the pipeline in a special test mode. This practice run is
different: it is set up **exactly the way your own run will be** — a folder of
FASTQ files, a reference genome, and a params file — only with a tiny dataset.

It is worth doing once, and worth keeping. If the pipeline later works with the
example but fails with your data, you can compare the two folders and the two
params files side by side to find what is different.

Download the data and the ready-made params file — this copies and pastes as
one block:

```bash
mkdir -p /mnt/lustre/users/$USER/nf-example
cd /mnt/lustre/users/$USER/nf-example

BASE=https://raw.githubusercontent.com/nf-core/test-datasets/modules/data/genomics/sarscov2
mkdir -p example-data/fastq example-data/references/sarscov2
curl -L -o example-data/references/sarscov2/genome.fasta $BASE/genome/genome.fasta
curl -L -o example-data/fastq/SAMPLE1_R1.fastq.gz $BASE/illumina/fastq/test_1.fastq.gz
curl -L -o example-data/fastq/SAMPLE1_R2.fastq.gz $BASE/illumina/fastq/test_2.fastq.gz
curl -L -o example-data/fastq/SAMPLE2_R1.fastq.gz $BASE/illumina/fastq/test2_1.fastq.gz
curl -L -o example-data/fastq/SAMPLE2_R2.fastq.gz $BASE/illumina/fastq/test2_2.fastq.gz

curl -O https://raw.githubusercontent.com/EIT-GBI/nf-dnaseq/main/params.example.yaml
echo "workflow.output.mode = 'link'" > lustre.config
```

**You should now have** this, which is the same shape your own data will
take:

```text
nf-example/
├── params.example.yaml          the ready-made settings file
├── lustre.config                a storage workaround, explained in Step 5
└── example-data/
    ├── fastq/
    │   ├── SAMPLE1_R1.fastq.gz  two samples, each an R1 + R2 pair
    │   ├── SAMPLE1_R2.fastq.gz
    │   ├── SAMPLE2_R1.fastq.gz
    │   └── SAMPLE2_R2.fastq.gz
    └── references/
        └── sarscov2/
            └── genome.fasta     a small virus genome (~30 KB)
```

Check with `ls -R example-data`. Nothing in `params.example.yaml` needs editing
— open it if you like (`nano params.example.yaml`) to see how it points at
these files.

Then submit it with the same command you will use for your own data
([Step 6](#step-6--start-the-run)), with `params.example.yaml` in place of
`params.cluster.yaml`:

```bash
module load nextflow
sbatch -J nf-example -p cpu -t 04:00:00 \
  --wrap='nextflow run EIT-GBI/nf-dnaseq -latest -params-file params.example.yaml -profile cluster -c lustre.config -resume'
```

Once it has left `squeue`, `tail -30 slurm-<job number>.out` should show
`Succeeded   : 23`, and there will be a `results` folder laid out as in
[Step 8](#step-8--collect-your-results).

> Do not copy the example's relative paths or its variant-calling thresholds
> (all set to `0`, because the example has so few reads) into your own params
> file. Use full `/mnt/lustre/...` paths and the values from
> `params.cluster.yaml`.

---

## Step 3 — Make your working folder

Each dataset gets two folders on Lustre, not in your home folder:

- a **run folder**, where your settings files and results go;
- a **work folder**, where Nextflow keeps its large temporary data. Keeping it
  apart means you can delete it in one go once the run is finished
  ([Step 8](#step-8--collect-your-results)).

First give your dataset a name. Change `my-first-run` to something that
describes your data:

```bash
DATASET_NAME=my-first-run
```

Then make the two folders and go into the run folder:

```bash
RUN_DIR=/mnt/lustre/users/$USER/data/$DATASET_NAME
export NXF_WORK=/mnt/lustre/users/$USER/nf-work/$DATASET_NAME
mkdir -p $RUN_DIR
mkdir -p $NXF_WORK
cd $RUN_DIR
```

`NXF_WORK` is the setting Nextflow reads to know where its work folder is.

> These settings only last until you log out. If you log out before
> [Step 6](#step-6--start-the-run), run both blocks above again (with the same
> dataset name) before you submit — otherwise Nextflow puts its temporary data
> inside your run folder.

Everything from here on happens in the run folder.

Put your FASTQ files in a folder of their own. They must be in pairs, named
like this:

```text
SAMPLENAME_R1.fastq.gz
SAMPLENAME_R2.fastq.gz
```

`SAMPLENAME` becomes the sample name in your results. `.fq.gz`, `.fastq` and
`.fq` also work, and an extra `_001` before the extension is fine.

**If your reads are already on Lustre, do not copy them.** Just set
`fastq_dir` (Step 5) to the folder they are already in. If
that folder also holds files you do not want analysed, or the files need
renaming, make a folder of shortcuts instead — a shortcut takes up no space:

```bash
mkdir -p fastq
ln -s /mnt/lustre/path/to/your/reads/*.fastq.gz fastq/
ls -l fastq/
```

To give a file a different name, make its shortcut under the new name:
`ln -s /mnt/lustre/path/to/old_name.fastq.gz fastq/SAMPLE1_R1.fastq.gz`.

Only if your reads are *not* on Lustre yet (for example, they are in Object
Storage) do you copy them in:

```bash
mkdir -p fastq
cp /wherever/your/reads/are/*.fastq.gz fastq/
ls fastq/
```

---

## Step 4 — Put your reference genome in place

Keep your genomes in one place, separate from any single run, with each genome
in its own subfolder:

```text
/mnt/lustre/users/YOU/references/
├── mouse/
│   └── genome.fasta
└── human/
    └── genome.fasta
```

```bash
mkdir -p /mnt/lustre/users/$USER/references/mouse
cp /wherever/your/genome/is/genome.fasta /mnt/lustre/users/$USER/references/mouse/
```

As with the reads: if the genome is already on Lustre (yours from an earlier
project, or a colleague's), do not copy it. Either set `reference_dir` and
`reference_genome` (Step 5) to where it already is, or make a shortcut to its
whole **folder** — not to the `.fasta` on its own, or the pipeline will not find
the index files that sit beside it:

```bash
mkdir -p /mnt/lustre/users/$USER/references
ln -s /mnt/lustre/path/to/mouse /mnt/lustre/users/$USER/references/mouse
```

If that folder has no index files yet and it is not yours, ask its owner to run
the indexing step below, rather than taking a copy to index yourself.

A plain `.fasta` is enough: if the `bwa` and `samtools` index files are not
there, the pipeline builds them for you.

### Large genomes: index once

The catch is that the pipeline rebuilds those indexes in every new run folder.
For a mouse or human genome that is over an hour wasted each time, so build them
once by hand and every future run will reuse them:

```bash
curl -O https://raw.githubusercontent.com/EIT-GBI/nf-dnaseq/main/scripts/index_reference.sbatch

sbatch index_reference.sbatch /mnt/lustre/users/$USER/references/mouse/genome.fasta
```

This runs on a compute node and may wait before it starts — that is Slurm
queuing it. It skips any index that already exists. For a human-sized genome,
give it more memory: `sbatch --mem=32G index_reference.sbatch ...`.

Check on it with `squeue -u $USER`; once it has finished, its log is in
`index-reference-<job number>.out`.

**You should see** seven files next to your `.fasta`:

```text
genome.fasta      genome.fasta.ann  genome.fasta.fai  genome.fasta.sa
genome.fasta.amb  genome.fasta.bwt  genome.fasta.pac
```

---

## Step 5 — Create your two settings files

### The settings file you edit

```bash
curl -O https://raw.githubusercontent.com/EIT-GBI/nf-dnaseq/main/params.cluster.yaml
nano params.cluster.yaml
```

Set these, replacing `YOU` with your username (`echo $USER` if unsure):

```yaml
samplesheet: null
fastq_dir: "/mnt/lustre/users/YOU/data/my-first-run/fastq"
reference_dir: "/mnt/lustre/users/YOU/references"
reference_genome: "mouse/genome.fasta"
outdir: "./results"
```

Settings you may want later, further down the same file:

| Setting | What it does |
| --- | --- |
| `alignment: device:` | `cpu` (default) or `gpu` for the much faster Parabricks alignment |
| `skip_variant_calling:` | `true` to stop after alignment and coverage |
| `variant_callers:` | `bcftools` (CPU), `deepvariant`, `mutect2` (both GPU) |
| `min_depth`, `min_qual` | how strict variant calling is |

The full list is in
[the pipeline's README](https://github.com/EIT-GBI/nf-dnaseq#key-parameters).

### The settings file you do not edit

This one-line file works around a storage problem on the cluster. Create it once
in each run folder and then forget about it:

```bash
echo "workflow.output.mode = 'link'" > lustre.config
```

> **While this file is in use, leave `outdir` as `./results`.** The workaround
> publishes results as links rather than copies, and a link cannot point across
> disks - so an `outdir` somewhere outside this folder, in your home directory
> say, makes the run fail when it tries to publish. This is temporary: once the
> storage fault is fixed, the pipeline goes back to writing real copies and the
> restriction goes with it.

---

## Step 6 — Start the run

From your run folder, check the work folder is still set — this should print
the `nf-work` path from Step 3, not an empty line:

```bash
echo $NXF_WORK
```

Then submit:

```bash
module load nextflow
sbatch -J nf-dnaseq -p cpu -t 5-00:00:00 \
  --wrap='nextflow run EIT-GBI/nf-dnaseq -latest -params-file params.cluster.yaml -profile cluster -c lustre.config -resume'
```

**You should see:**

```text
Submitted batch job 519583
```

Write that number down. The run now continues on its own, even if you close your
laptop.

| Part | What it does |
| --- | --- |
| `module load nextflow` | Makes Nextflow available. The job takes it, and `NXF_WORK`, from your session when you submit. |
| `-J nf-dnaseq` | Names the job, so you can spot it in `squeue`. |
| `-p cpu` | Correct even for GPU pipelines — this job is only Nextflow itself, and the GPU steps ask for GPU nodes on their own. |
| `-t 5-00:00:00` | Five days. Nextflow lives as long as the whole pipeline. |
| `EIT-GBI/nf-dnaseq` | The pipeline on GitHub. Nextflow downloads it for you; no need to copy it yourself. |
| `-latest` | Fetch the newest version of the pipeline. |
| `-profile cluster` | Use Slurm and the cluster's containers. |
| `-resume` | Reuse anything already finished. Always safe to include. |

---

## Step 7 — Check how it is going

```bash
squeue -u $USER
```

You will see `nf-dnaseq` (Nextflow itself) plus one line per pipeline step
currently running. A step showing `PD` is queued and waiting, not broken.

Read how far it has got:

```bash
tail -30 slurm-519583.out
```

(Use your own job number.) Run it again whenever you want an update.

> **Please check in this way, rather than leaving a command running that follows
> the log.** The login node is shared by everyone, and long-lived watching
> commands add up. A run continues perfectly well without anyone watching it.

Once the job has disappeared from `squeue`, confirm how it ended:

```bash
sacct -j 519583 --format=JobID,JobName,State,Elapsed
```

`COMPLETED` means it finished; `FAILED` or `TIMEOUT` means read the log.

To stop a run, cancel the Nextflow job — it cleans up the rest:

```bash
scancel 519583
```

---

## Step 8 — Collect your results

Your results are in `results`:

```text
results/
├── samplesheet/      the list of samples the run used, built from your fastq folder
├── trimmed/          fastp trimming reports (open the .html in a browser)
├── qc/fastqc/        FastQC read-quality reports (.html)
├── qc/flagstat/      alignment summary numbers
├── alignment/        sorted BAM files + their indexes
├── bigwig/           coverage tracks for a genome browser
├── consensus/        consensus sequence per sample
└── variants/         variant calls (VCF)
```

`samplesheet/samplesheet.csv` is worth a glance on your first run: it records
which FASTQ files were paired together and what each sample ended up being
called. If a sample is missing from your results, this is where it shows.

The commands below use `DATASET_NAME`. If you have logged out since Step 3, set
it again first, with the same name as before:

```bash
DATASET_NAME=my-first-run
cd /mnt/lustre/users/$USER/data/$DATASET_NAME
```

**One important step before you delete anything.** Because of the `lustre.config`
workaround, the results are currently shortcuts pointing into the `work` folder
rather than real files. Turn them into real files:

```bash
rsync -aL results/ results-final/
```

(This is the one Lustre-to-Lustre copy the guide asks for, and it is short-lived:
you delete the work folder straight after and move `results-final` off Lustre at
the end.)

Check that worked — this should print `0`:

```bash
find results-final -type l | wc -l
```

Now delete the work folder from Step 3, which is much bigger than your results:

```bash
rm -rf /mnt/lustre/users/$USER/nf-work/$DATASET_NAME
```

> Only do this once you are happy with the run. Deleting the work folder means a
> future `-resume` has to start from scratch.

Finally, move `results-final` off Lustre. This matters: Lustre is fast but
expensive, so it cannot simply be expanded when it fills up. It is shared by
everyone, and it only works as scratch space for active analyses if finished
data is moved off promptly. Your Object Storage area is far cheaper and is where
results belong once a run is done.

```bash
module load gbi
gbi data move --detach \
  /mnt/lustre/users/$USER/data/$DATASET_NAME/results-final \
  /mnt/user-data/$USER/$DATASET_NAME/results
```

`--detach` runs the transfer as a Slurm job so it survives you logging out.
`gbi data roots` shows the storage areas available to you, and
`gbi data status <job number>` shows how a transfer is going. See the
[moving data guide](https://github.com/EIT-GBI/scientific-computing-docs/blob/main/sections/moving-data/README.md).

---

## Running it again

For a new dataset: pick a new dataset name, make its two folders as in Step 3,
copy your settings files into the run folder, edit the paths, and submit again.
Run this from the previous run folder, so the `cp` finds your settings files:

```bash
DATASET_NAME=my-second-run
RUN_DIR=/mnt/lustre/users/$USER/data/$DATASET_NAME
export NXF_WORK=/mnt/lustre/users/$USER/nf-work/$DATASET_NAME
mkdir -p $RUN_DIR
mkdir -p $NXF_WORK
cp params.cluster.yaml lustre.config $RUN_DIR/
cd $RUN_DIR
nano params.cluster.yaml

module load nextflow
sbatch -J nf-dnaseq -p cpu -t 5-00:00:00 \
  --wrap='nextflow run EIT-GBI/nf-dnaseq -latest -params-file params.cluster.yaml -profile cluster -c lustre.config -resume'
```

---

## If something goes wrong (on the cluster)

Start by reading the end of your log:

```bash
tail -50 slurm-<your job number>.out
```

| What you see | What it means | What to do |
| --- | --- | --- |
| `nextflow: command not found` | Nextflow was not loaded when you submitted. | Run `module load nextflow`, then the `sbatch` command again. |
| A `work` folder appears inside your run folder | `NXF_WORK` was not set when you submitted, usually after logging out and back in. | Cancel the run, delete that `work` folder, redo the `export NXF_WORK=...` line from Step 3, and submit again. |
| `Lmod has detected the following error: ... nextflow` | The Nextflow module is not available yet. | Check with `module avail nextflow`, then ask the platform team. |
| `command not found` for a container tool | Nextflow was started on the login node instead of as a job. | Always start it with `sbatch`, never by typing `nextflow run ...` directly. |
| `Failed to publish file: ... No data available` | A known Lustre storage fault: the copy step intermittently fails on files written moments earlier. | Make sure `lustre.config` exists and `-c lustre.config` is in your command, then submit again. Please also [report it](https://github.com/EIT-GBI/gbi-sandpit-cluster/issues). |
| `does not exist` for your FASTQ or genome | A path in `params.cluster.yaml` is wrong. | Check each one with `ls "<the path>"`. Use full paths starting `/mnt/lustre/...`. |
| Only some samples appear | A FASTQ pair is misnamed. | Every sample needs both `_R1` and `_R2`. |
| Nothing happens, jobs stuck on `PD` | The cluster is busy. | Wait. `sinfo` shows how busy. |
| `No such file or directory` writing results | Lustre may be full. | `df -h /mnt/lustre`, and move old data off. |

When asking for help, include: what you were trying to do, the exact error, and
your `slurm-<number>.out` file.

---
---

# Part 2 — Running on your own computer

This part is optional. Use it to try the pipeline out on small data; run your
real analyses on the cluster ([Part 1](#part-1--running-on-the-gbi-cluster)).

## What you can and cannot do here

**You can:** run the whole standard pipeline — trimming, QC, alignment,
coverage and `bcftools` variant calling.

**You cannot:** use the GPU steps. GPU alignment (`alignment.device: gpu`) and
the `deepvariant` and `mutect2` callers all need NVIDIA Parabricks, which needs
cluster GPUs. Leave those settings alone here and use Part 1 instead.

Be realistic about size. A viral or bacterial genome runs in seconds. A mouse or
human genome will take many hours on a laptop, if it finishes at all — that is
what the cluster is for.

> **On an Apple Silicon Mac (M1–M4)?** Fine. All of the pipeline's containers are
> built for both Intel and ARM, so they run natively with no emulation.

---

## Step 1 — Install Docker

Download **Docker Desktop** from
[docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
and install it like any other application.

Then **start it** — Docker has to be running before the pipeline will work. You
will see a whale icon in your menu bar or system tray.

Check it from a terminal:

```bash
docker info
```

**You should see** a block of information about your Docker setup. If instead
you see `Cannot connect to the Docker daemon`, Docker is not running yet — open
the Docker Desktop application and wait for it to finish starting.

---

## Step 2 — Install Java and Nextflow

Nextflow needs Java 17 or newer. Install Java first:

```bash
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 17.0.10-tem
```

Then Nextflow:

```bash
mkdir -p "$HOME/.local/bin"
cd "$HOME/.local/bin"
curl -s https://get.nextflow.io | bash
chmod +x nextflow
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

> Using a Mac with the default `zsh` shell? Change `~/.bashrc` to `~/.zshrc` in
> that last line.

Open a new terminal and check:

```bash
nextflow -version
```

**You should see** `version 26.04.x` or newer. The pipeline needs **26.04.4 or
higher**; if yours is older, run `nextflow self-update`.

---

## Step 3 — Check it works

The pipeline comes with a tiny test dataset — a small SARS-CoV-2 genome and two
FASTQ pairs — which it downloads for you. Nothing to prepare.

```bash
mkdir -p ~/nf-test
cd ~/nf-test

nextflow run EIT-GBI/nf-dnaseq -latest -profile test,docker
```

The first run takes a few minutes while it downloads the tool containers. After
that it takes well under a minute.

**You should see**, at the end:

```text
[SUCCESS] completed=21 failed=0 cached=0
```

If you see that, everything is installed correctly and you can delete this
folder.

---

## Optional — A practice run with example data

The same practice run as
[on the cluster](#optional--a-practice-run-with-example-data): set up exactly
the way your own run will be, only with a tiny dataset, so it finishes in a
minute or two. Make a folder for it and download the data. This copies and
pastes as one block:

```bash
mkdir -p ~/nf-example
cd ~/nf-example

BASE=https://raw.githubusercontent.com/nf-core/test-datasets/modules/data/genomics/sarscov2
mkdir -p example-data/fastq example-data/references/sarscov2
curl -L -o example-data/references/sarscov2/genome.fasta $BASE/genome/genome.fasta
curl -L -o example-data/fastq/SAMPLE1_R1.fastq.gz $BASE/illumina/fastq/test_1.fastq.gz
curl -L -o example-data/fastq/SAMPLE1_R2.fastq.gz $BASE/illumina/fastq/test_2.fastq.gz
curl -L -o example-data/fastq/SAMPLE2_R1.fastq.gz $BASE/illumina/fastq/test2_1.fastq.gz
curl -L -o example-data/fastq/SAMPLE2_R2.fastq.gz $BASE/illumina/fastq/test2_2.fastq.gz

curl -O https://raw.githubusercontent.com/EIT-GBI/nf-dnaseq/main/params.example.yaml
```

**You should now have** this, which is the same shape your own data will
take:

```text
nf-example/
├── params.example.yaml          the ready-made settings file
└── example-data/
    ├── fastq/
    │   ├── SAMPLE1_R1.fastq.gz  two samples, each an R1 + R2 pair
    │   ├── SAMPLE1_R2.fastq.gz
    │   ├── SAMPLE2_R1.fastq.gz
    │   └── SAMPLE2_R2.fastq.gz
    └── references/
        └── sarscov2/
            └── genome.fasta     a small virus genome (~30 KB)
```

Check with `ls -R example-data`. Nothing in `params.example.yaml` needs editing
— open it if you like (`nano params.example.yaml`) to see how it points at
these files.

Then run it with the same command you will use for your own data:

```bash
nextflow run EIT-GBI/nf-dnaseq -latest \
  -params-file params.example.yaml -profile docker -resume
```

**You should see**, at the end:

```text
[SUCCESS] completed=23 failed=0 cached=0
```

and a `results` folder laid out as in [Step 6](#step-6--your-results).

> **Two things in `params.example.yaml` you should not copy for your own data.**
> Its paths are relative (`./example-data/...`), which only works because the
> data sits inside the run folder — for your own data, use full paths. And its
> variant-calling thresholds (`min_depth`, `min_qual`, `min_mapq`) are set to
> `0`, because the example has too few reads to pass normal ones. Keep the
> values from `params.cluster.yaml` for real data.

---

## Step 4 — Set up your own run

Make a folder for your dataset and go into it:

```bash
mkdir -p ~/my-first-run
cd ~/my-first-run
```

Put your FASTQ files in a folder of their own. They must be in pairs, named
like this:

```text
SAMPLENAME_R1.fastq.gz
SAMPLENAME_R2.fastq.gz
```

`SAMPLENAME` becomes the sample name in your results. `.fq.gz`, `.fastq` and
`.fq` also work, and an extra `_001` before the extension is fine.

```bash
mkdir -p fastq
cp /wherever/your/reads/are/*.fastq.gz fastq/
ls fastq/
```

Put your reference genome somewhere too, with each genome in its own subfolder:

```text
~/references/
└── sarscov2/
    └── genome.fasta
```

A plain `.fasta` is enough — the pipeline builds the index files it needs. (See
[Large genomes](#large-genomes-index-once) in Part 1 if that changes for you.)

Now fetch the settings template and edit it:

```bash
curl -O https://raw.githubusercontent.com/EIT-GBI/nf-dnaseq/main/params.cluster.yaml
mv params.cluster.yaml params.yaml
nano params.yaml
```

Set these paths; leave the rest alone:

```yaml
samplesheet: null
fastq_dir: "/Users/you/my-first-run/fastq"
reference_dir: "/Users/you/references"
reference_genome: "sarscov2/genome.fasta"
outdir: "./results"
```

Use **full paths**, not `~`. Run `pwd` in a folder to see its full path.

> **How `reference_dir` and `reference_genome` fit together:** the pipeline
> joins them, so the example above looks for
> `/Users/you/references/sarscov2/genome.fasta`.

Then find the `variant_callers` block further down and **comment out
`deepvariant`**, so only `bcftools` is left:

```yaml
variant_callers:
  - bcftools
#  - deepvariant
#  - mutect2
```

This one matters. The file ships with `deepvariant` switched on, and
`deepvariant` is a GPU step: left in, your run downloads a multi-gigabyte
NVIDIA container and then fails for want of a graphics card. `bcftools` is the
one that works here.

In `nano`, use the arrow keys to move around, then `Ctrl-O` and `Enter` to save,
and `Ctrl-X` to quit.

---

## Step 5 — Run it

```bash
nextflow run EIT-GBI/nf-dnaseq -latest \
  -params-file params.yaml -profile docker -resume
```

Progress appears as it goes. Leave the terminal open until it finishes —
closing it stops the run.

If something fails, fix it and run the same command again. Thanks to `-resume`,
finished steps are not repeated.

---

## Step 6 — Your results

Everything is in the `results` folder:

```text
results/
├── samplesheet/      the list of samples the run used, built from your fastq folder
├── trimmed/          fastp trimming reports (open the .html in a browser)
├── qc/fastqc/        FastQC read-quality reports (.html)
├── qc/flagstat/      alignment summary numbers
├── alignment/        sorted BAM files + their indexes
├── bigwig/           coverage tracks for a genome browser
├── consensus/        consensus sequence per sample
└── variants/         variant calls (VCF)
```

These are real files, so you can move or copy them anywhere.

`samplesheet/samplesheet.csv` is worth a glance on your first run: it records
which FASTQ files were paired together and what each sample ended up being
called. If a sample is missing from your results, this is where it shows.

The `work` folder holds the intermediate files and is much larger. Once you are
happy with your results, delete it:

```bash
rm -rf work
```

---

## If something goes wrong (on your computer)

| What you see | What to do |
| --- | --- |
| `Cannot connect to the Docker daemon` | Docker is not running. Open Docker Desktop and wait for it to start. |
| `Nextflow version ... does not match` | `nextflow self-update` |
| `does not exist` for your FASTQ or genome | A path in `params.yaml` is wrong. Check each with `ls "<the path>"`, and use full paths. |
| Only some samples appear | Every sample needs both an `_R1` and an `_R2` file. |
| A step is killed, or the run dies with no clear error | Docker has too little memory. In Docker Desktop, go to Settings → Resources and raise the memory limit. |
| It has been running for hours | Your genome is probably too big for a laptop. Use the cluster (Part 1). |
| `No space left on device` | Docker images and `work/` fill up disks. `rm -rf work`, and `docker system prune` to clear unused images. |
